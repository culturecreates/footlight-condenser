require "tempfile"

module Distillator
  class TransitionCheckRunner
    REQUEST_BUDGET_SECONDS = 20
    TIMEOUT_GUARD_SECONDS = 3
    MEMORY_SAMPLE_INTERVAL = 10
    CHECKPOINT_BATCH_SIZE = 10
    CacheMetadata = Struct.new(:normalized_url, :primary_issue_key, :http_response_code)

    Result = Struct.new(:website, :records, keyword_init: true) do
      def flash_message
        prefix = complete? ? "Transition check recorded:" : "Transition check incomplete:"
        "#{prefix} #{summary_items.join(', ')}"
      end

      def complete?
        summary_statuses.values.all? { |status| status == "checked" }
      end

      def summary_statuses
        records.transform_values { |record| summary_status_for(record) }
      end

      private

      def summary_status_for(record)
        reason = record.details.to_h["reason"] || record.details.to_h[:reason]
        return "not evaluated" if reason == "fetch_failed_before_statement_refresh"
        return "blocked by fetch" if reason == "fetch_failed_before_export_comparison"
        return "inconclusive" if %w[
          no_selected_statements
          paired_extraction_inconclusive
          export_diff_not_available
          partial_fetch_failed_before_statement_refresh
          partial_fetch_failed_before_export_comparison
          transition_check_timeout_budget_exceeded
        ].include?(reason)

        case record.status.to_s
        when "checked", "accepted"
          "checked"
        when "failed", "blocked", "rejected"
          "failed"
        else
          "missing"
        end
      end

      def summary_items
        [
          "fetch #{summary_statuses.fetch(:fetch_parity)}",
          "statements #{summary_statuses.fetch(:statement_delta)}",
          "export #{summary_statuses.fetch(:export_diff)}"
        ]
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(
      website:,
      refresh_helper: nil,
      transition_run: nil,
      check_options: nil,
      statement_comparator: Distillator::MigrationComparator,
      refresh_runner: Distillator::RefreshRunner,
      export_service: ExportArtsdataService,
      transition_check_service: Distillator::TransitionCheck,
      fetch_cache_store: Distillator::FetchCacheStore,
      cache_compare: Distillator::CacheCompare,
      budget_seconds: nil,
      timeout_guard_seconds: TIMEOUT_GUARD_SECONDS,
      clock: nil,
      memory: Distillator::TransitionMemory.new,
      verify_active_path: false,
      require_native_path: false,
      cancellation_check: nil
    )
      @transition_run = transition_run
      @check_options = transition_run ? transition_run.options : Distillator::TransitionCheckOptions.coerce(check_options)
      if transition_run && check_options && Distillator::TransitionCheckOptions.coerce(check_options).to_h != @check_options.to_h
        raise ArgumentError, "Check options must match the recorded run"
      end
      @statement_comparator = statement_comparator
      @website = website.is_a?(Website) ? website : Website.find(website)
      @refresh_helper = refresh_helper || StatementsHelper.build_refresh_proxy(cookies: {})
      @memory = memory
      @export_service = export_service
      @transition_check_service = transition_check_service
      @fetch_cache_store = fetch_cache_store
      @cache_compare = cache_compare
      @budget_seconds = budget_seconds
      @timeout_guard_seconds = timeout_guard_seconds
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @started_at = monotonic_now
      @representative_result_cache = {}
      @applicable_sources = {}
      @verify_active_path = verify_active_path
      @require_native_path = require_native_path || verify_active_path
      @cancellation_check = cancellation_check
    end

    def call
      return perform_checks if transition_run

      request = Distillator::TransitionRun.request!(website: website, options: @check_options)
      raise "A transition check is already running" unless request.created?
      @transition_run = request.run
      transition_run.execute { perform_checks }
    end

    def perform_checks
      # Active Record's query cache can otherwise retain each fetched body, even
      # after the comparison releases the corresponding model.
      ActiveRecord::Base.uncached do
        Tempfile.create("distillator-html", anonymous: true, binmode: true) do |file|
          @snapshot_file = file
          perform_checks_with_snapshots
        end
      end
    ensure
      @snapshot_file = nil
      @representative_url_results = nil
      @representative_result_cache.clear
      @applicable_sources.clear
      @memory.record(run_id: transition_run.id, phase: "after_cleanup", enforce_limit: false)
    end

    private

    def perform_checks_with_snapshots
      @cancellation_check&.call
      transition_run.prepare_discovery!(cancellation_check: @cancellation_check)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @phase_timings = {}
      transition_run&.record_progress!("selection")
      @memory.record(run_id: transition_run.id, phase: "selection")
      check_args = { website: website, run_fetch: false, scope_at: transition_run.started_at || transition_run.requested_at }
      check_args[:check_options] = @check_options unless @check_options.default?
      check_args[:sample_run] = transition_run if @check_options.default?
      transition_check = timed_phase("selection") { transition_check_service.call(**check_args) }
      if @check_options.strict? && !@check_options.include_retired? && inventory_details(transition_check)&.fetch(:status) == "active_event_scope"
        transition_run.record_discovery_at_start!(check_args.fetch(:scope_at))
      end
      representative_webpages = Array(transition_check.representative_webpages)
      if transition_run.resumable? && (representative_webpages.length > CHECKPOINT_BATCH_SIZE || transition_run.transition_checkpoints.exists?)
        return perform_checkpoint_batch(transition_check, representative_webpages, started)
      end
      record_page_progress("fetch", 0, representative_webpages.length)
      representative_url_results = @representative_url_results = timed_phase("fetch") do
        collect_representative_url_results(representative_webpages, transition_check.comparison_policy)
      end
      @snapshot_file.flush
      @memory.record(run_id: transition_run.id, phase: "after_fetch",
        completed: representative_url_results.count { |row| row[:attempted_condenser_fetch] }, total: representative_webpages.length)

      finish_checks(transition_check, representative_webpages, representative_url_results, started)
    end

    def perform_checkpoint_batch(check, webpages, started)
      checkpoints = transition_run.transition_checkpoints.order(:offset)
      scope = Digest::SHA256.hexdigest(JSON.generate([
        ENV["HEROKU_RELEASE_VERSION"] || ENV["SOURCE_VERSION"] || Digest::SHA256.file(__FILE__).hexdigest,
        transition_run.configuration_digest, website.distillator_mode, @verify_active_path, @require_native_path,
        check.comparison_policy, webpages.map { |page| [page.id, page.url] }, inventory_details(check),
        DslLibraryEntry.order(:id).pluck(:name, :body, :revision, :aliases),
        WringerEndpoint.current.legacy_lookup_base_url
      ]))
      saved_scope = checkpoints.limit(1).pick(Arel.sql("payload ->> 'scope'"))
      if saved_scope && saved_scope != scope
        raise TransitionRun::ConfigurationChanged, "Checkpoint scope or release changed. Run a new check."
      end

      offset = checkpoints.sum(:page_count)
      if offset > webpages.length || timeout_budget_exceeded?
        raise TransitionRun::ConfigurationChanged, "Verification coverage is incomplete. Run a new check."
      end
      if offset == webpages.length
        return TransitionRun.transaction { complete_checkpointed_check(check, webpages, checkpoints, scope, started) }
      end

      attempt = transition_run.progress.fetch("batch_attempts", 1)
      batch_size = [CHECKPOINT_BATCH_SIZE / (2**(attempt - 1)), 1].max
      batch = webpages.slice(offset, batch_size)
      record_page_progress("fetch", offset, webpages.length)
      inputs = timed_phase("fetch") do
        collect_representative_url_results(batch, check.comparison_policy, offset: offset, total: webpages.length)
      end
      @snapshot_file.flush
      record_page_progress("statements", offset, webpages.length)
      parity = timed_phase("statements") { compare_statements(batch, inputs, offset: offset, total: webpages.length) }
      if timeout_budget_exceeded?
        raise TransitionRun::ConfigurationChanged, "Check expired before finishing this batch. Coverage is incomplete."
      end

      transition_run.save_checkpoint!(offset: offset, page_count: batch.length, payload: {
        scope: scope,
        fetch: inputs.map { |row| serializable_representative_url_result(row).merge(cache: row[:cache]&.to_h) },
        rows: parity.url_results, artifacts: parity.artifacts, comparison_count: parity.comparison_count, timings: parity.timings,
        phases_ms: @phase_timings
      })
      @memory.record(run_id: transition_run.id, phase: "checkpoint_saved", completed: offset + batch.length,
        total: webpages.length, profile: { html_snapshot_bytes: @snapshot_file.size }, enforce_limit: false)
      TransitionRun::CONTINUE
    end

    def complete_checkpointed_check(check, webpages, checkpoints, checkpoints_scope, started)
      # A worker can stop after committing the final evidence but before
      # changing the run status. The evidence transaction commits all phases.
      records = transition_run.transition_evidences.where(check_kind: TransitionEvidence::REPORT_CHECK_KINDS)
        .index_by { |record| record.check_kind.to_sym }
      if records.size == TransitionEvidence::REPORT_CHECK_KINDS.size
        return Result.new(website: website, records: records)
      end

      inputs = []
      rows = []
      artifacts = []
      count = 0
      timings = {}
      checkpoints.reorder(nil).find_each(batch_size: 1) do |checkpoint|
        @cancellation_check&.call
        payload = checkpoint.payload
        fetch = payload.fetch("fetch")
        batch_rows = payload.fetch("rows")
        expected_pages = webpages.slice(inputs.length, checkpoint.page_count)
        if expected_pages.nil? || payload.fetch("scope") != checkpoints_scope || checkpoint.offset != inputs.length ||
            fetch.map { |row| row.fetch("webpage_id") } != expected_pages.map(&:id) ||
            batch_rows.map { |row| row.fetch("url") } != expected_pages.map(&:url)
          raise TransitionRun::ConfigurationChanged, "Checkpoint coverage could not be verified. Run a new check."
        end

        inputs.concat(fetch.map do |row|
          restored = row.symbolize_keys
          restored[:cache] = CacheMetadata.new(*row["cache"].values_at("normalized_url", "primary_issue_key", "http_response_code")) if row["cache"]
          restored
        end)
        rows.concat(batch_rows.map(&:symbolize_keys))
        artifacts.concat(payload.fetch("artifacts").map(&:symbolize_keys))
        count += payload.fetch("comparison_count")
        payload.fetch("timings").each do |source_id, data|
          timing = timings[source_id] ||= data.symbolize_keys.merge(executions: 0, extraction_ms: 0.0, formatting_ms: 0.0)
          %i[executions extraction_ms formatting_ms].each { |key| timing[key] += data.fetch(key.to_s) }
        end
        payload.fetch("phases_ms").each { |phase, time| @phase_timings[phase] = @phase_timings.fetch(phase, 0) + time }
      end
      parity = StatementParityCheck.summarize(rows: rows, artifacts: artifacts, comparison_count: count,
        timings: timings, strict: @check_options.strict?)
      @representative_url_results = inputs
      finish_checks(check, webpages, inputs, started, parity: parity, checkpointed: true)
    end

    def finish_checks(transition_check, representative_webpages, representative_url_results, started, parity: nil, checkpointed: false)
      @cancellation_check&.call
      records = {
        fetch_parity: record_fetch_check(transition_check, representative_url_results),
        statement_delta: timed_phase("statements") { record_statement_check(transition_check, representative_webpages, representative_url_results, parity: parity) },
        export_diff: timed_phase("export") { record_export_check(transition_check, representative_webpages, representative_url_results) }
      }
      transition_run&.record_progress!("completed", completed: representative_webpages.length, total: representative_webpages.length)
      @memory.record(run_id: transition_run.id, phase: "finalizing")
      elapsed = checkpointed ? Time.current - transition_run.started_at : Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      performance = { total_ms: (elapsed * 1000).round(2), phases_ms: @phase_timings.dup,
        slowest_sources: Array(records[:statement_delta].details["slowest_sources"]) }
      records[:export_diff].update!(details: records[:export_diff].details.merge("performance" => performance))
      Rails.logger.info(event: "distillator.transition.performance", website_id: website.id, run_id: transition_run&.id, performance: performance)
      Result.new(website: website, records: records)
    end

    def record_page_progress(phase, completed, total, timings: nil)
      return unless transition_run

      updated = transition_run.record_progress!(phase, completed: completed, total: total)
      raise TransitionRun::ConfigurationChanged, "Transition check is no longer running." if updated.zero?

      sample = (completed % MEMORY_SAMPLE_INTERVAL).zero? || completed == total
      if sample && timings
        rows = timings.values
        profile = { paired_dsl_ms: rows.sum { |row| row[:extraction_ms] }.round(2),
          formatting_ms: rows.sum { |row| row[:formatting_ms] }.round(2),
          source_executions: rows.sum { |row| row[:executions] } }
      end
      @memory.record(run_id: transition_run.id, phase: phase, completed: completed, total: total,
        sample: sample, profile: profile)
    end

    attr_reader :transition_run, :statement_comparator, :website, :refresh_helper, :export_service, :transition_check_service, :fetch_cache_store, :cache_compare,
                :timeout_guard_seconds

    def timed_phase(name)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
      @phase_timings[name] = (@phase_timings.fetch(name, 0) + elapsed_ms).round(2)
    end

    def record_fetch_check(transition_check, representative_url_results)
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      status, details = fetch_check_payload(transition_check, representative_url_results)

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: representative_url_results.first&.dig(:url).presence || transition_check.representative_url.presence || cache_or_seed_url(latest_cache),
        check_kind: :fetch_parity,
        status: status,
        primary_issue_key: latest_cache&.primary_issue_key,
        wringer_http_code: latest_cache&.http_response_code,
        distillator_http_code: latest_cache&.http_response_code,
        details: details
      )
    end

    def record_statement_check(transition_check, representative_webpages, representative_url_results, parity: nil)
      record_page_progress("statements", 0, representative_webpages.length) unless parity
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      return record_missing_representatives(latest_cache, :statement_delta, transition_check) if representative_webpages.blank?
      if timeout_budget_exceeded?
        fetched, failed = partition_representative_webpages(representative_webpages, representative_url_results)
        return pending_statement_timeout_record(latest_cache, transition_check, representative_webpages, fetched, failed)
      end
      parity ||= compare_statements(representative_webpages, representative_url_results)
      critical = parity.critical_failures.map { |entry| failure_identity(entry) }
      optional = parity.optional_failures.map { |entry| failure_identity(entry) }
      Distillator::TransitionEvidenceRecorder.call(
        website: website, transition_run: transition_run,
        url: representative_webpages.first&.url.presence || cache_or_seed_url(latest_cache),
        check_kind: :statement_delta, status: parity.status,
        statement_delta: parity.critical_failures.length,
        statement_count_delta_acceptable: parity.status.in?(%i[checked warning]),
        details: scope_details(transition_check, representative_webpages).merge(
          source: "paired_extraction", comparison_basis: "paired_dsl", value_stage: StatementParityCheck::VALUE_STAGE,
          reason: parity.reason,
          representative_url_statement_results: parity.url_results,
          statement_artifacts: parity.artifacts,
          statements_compared_count: parity.comparison_count, statements_refreshed_count: 0,
          slowest_sources: parity.slowest_sources,
          compared_webpage_count: parity.url_results.count { |row| row[:status].in?(%w[passed warning failed unverified]) },
          shared_extraction_failure_count: parity.artifacts.count { |entry| MigrationComparator.shared_extraction_failure?(entry) },
          statements_failed_count: critical.length + optional.length, failing_statements: critical + optional,
          critical_statements_failed_count: critical.length,
          optional_statements_failed_count: optional.length,
          critical_failing_statements: critical, optional_failing_statements: optional
        )
      )
    end

    def compare_statements(webpages, inputs, offset: 0, total: webpages.length)
      StatementParityCheck.call(website: website, webpages: webpages,
        url_results: inputs, refresh_helper: refresh_helper, comparator: statement_comparator,
        strict: @check_options.strict?, stop_requested: method(:comparison_stop_requested?), compact_evidence: true,
        snapshot_reader: method(:read_html_pair), source_lookup: method(:selected_sources_for),
        progress: ->(completed, _, timings) { record_page_progress("statements", offset + completed, total, timings: timings) unless completed.zero? })
    end

    def comparison_stop_requested?
      @cancellation_check&.call
      timeout_budget_exceeded?
    end

    def failure_identity(entry)
      entry.except(:legacy, :condenser, :timing, :legacy_error, :condenser_error)
    end

    def record_export_check(transition_check, representative_webpages, representative_url_results)
      @cancellation_check&.call
      transition_run&.record_progress!("export")
      @memory.record(run_id: transition_run.id, phase: "export")
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      return record_missing_representatives(latest_cache, :export_diff, transition_check) if representative_webpages.blank?
      fetched_webpages, failed_fetch_results = partition_representative_webpages(representative_webpages, representative_url_results)

      if timeout_budget_exceeded?
        return pending_export_timeout_record(latest_cache, transition_check, representative_webpages, fetched_webpages, failed_fetch_results)
      end

      if representative_url_results.all? { |result| result[:fetch_status] == "failed" }
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
          transition_run: transition_run,
          url: cache_or_seed_url(latest_cache),
          check_kind: :export_diff,
          status: :pending,
          export_diff_status: "pending",
          details: scope_details(transition_check, representative_webpages).merge(
            source: "export_comparison",
            export_compared: false,
            export_basis: "current export vs production-equivalent export",
            representative_url_export_results: representative_url_results.map do |result|
              {
                url: result[:url],
                status: "blocked_by_fetch",
                reason: result[:fetch_reason]
              }
            end,
            reason: "fetch_failed_before_export_comparison"
          )
        )
      end

      actual = export_service.call(seedurl: website.seedurl)
      @cancellation_check&.call
      expected = export_service.production_equivalent(seedurl: website.seedurl)
      @cancellation_check&.call
      if Distillator::ExportNormalizer.blank_export?(actual) || Distillator::ExportNormalizer.blank_export?(expected)
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
          transition_run: transition_run,
          url: cache_or_seed_url(latest_cache),
          check_kind: :export_diff,
          status: :pending,
          export_diff_status: "pending",
          details: scope_details(transition_check, representative_webpages).merge(
            source: "export_comparison",
            export_compared: false,
            export_basis: "current export vs production-equivalent export",
            representative_url_export_results: representative_export_results(representative_webpages, failed_fetch_results, "inconclusive", "export_diff_not_available"),
            reason: "export_diff_not_available"
          )
        )
      end

      normalized_actual = Distillator::ExportNormalizer.normalize(actual)
      normalized_expected = Distillator::ExportNormalizer.normalize(expected)
      diff = Distillator::GraphDiff.call(expected_graph: normalized_expected, actual_graph: normalized_actual)
      failed = diff.added_count.positive? || diff.removed_count.positive? || diff.changed_literal_values.any? || diff.changed_uri_objects.any?
      status = failed ? :failed : :checked
      partial_fetch_coverage = failed_fetch_results.any?
      effective_status = partial_fetch_coverage ? :pending : status
      effective_export_checked = partial_fetch_coverage ? false : (status == :checked)
      effective_export_diff_status = partial_fetch_coverage ? "partial" : status.to_s

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: effective_status,
        export_diff_checked: effective_export_checked,
        export_diff_status: effective_export_diff_status,
        export_diff_accepted: false,
        rdf_added_count: diff.added_count,
        rdf_removed_count: diff.removed_count,
        details: scope_details(transition_check, representative_webpages).merge(
          source: "export_comparison",
          export_compared: !partial_fetch_coverage,
          graph_diff_performed: true,
          export_basis: "current export vs production-equivalent export",
          representative_url_export_results: representative_export_results(representative_webpages, failed_fetch_results, status.to_s, status == :checked ? "ok" : "export_diff_detected"),
          reason: partial_fetch_coverage ? "partial_fetch_failed_before_export_comparison" : nil,
          changed_literal_values: diff.changed_literal_values.first(10),
          changed_uri_objects: diff.changed_uri_objects.first(10)
        ).compact
      )
    rescue TransitionRun::Cancelled
      raise
    rescue StandardError => error
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: :failed,
        export_diff_status: "failed",
        details: scope_details(transition_check, representative_webpages).merge(
          export_compared: false,
          export_basis: "current export vs production-equivalent export"
        ).merge(failure_details("export_generation_failed", error))
      )
    end

    def fetch_check_payload(transition_check, representative_url_results)
      cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      representative_webpages = Array(transition_check.representative_webpages)
      details = scope_details(transition_check, representative_webpages).merge(
        source: "transition_check",
        attempted_condenser_fetch: representative_url_results.any? { |result| result[:attempted_condenser_fetch] },
        condenser_fetch_success: representative_url_results.any? { |result| result[:fetch_status] == "passed" },
        comparison_performed: representative_url_results.any? { |result| result[:comparison_performed] },
        comparison_policy: transition_check.comparison_policy.to_s,
        legacy_source: representative_url_results.first&.dig(:legacy_source),
        legacy_lookup_status: representative_url_results.first&.dig(:legacy_lookup_status),
        legacy_lookup_error: representative_url_results.first&.dig(:legacy_lookup_error),
        condenser_source: representative_url_results.first&.dig(:condenser_source),
        compare_missing: representative_url_results.first&.dig(:compare_missing),
        compare_summary: representative_url_results.first&.dig(:compare_summary),
        representative_url_results: representative_url_results.map { |result| serializable_representative_url_result(result) },
        failed_layer: representative_failed_layer(representative_url_results),
        affected_url_count: representative_affected_url_count(representative_url_results),
        representative_urls_checked: representative_url_results.any?
      ).compact
      details[:event_inventory] = inventory_details(transition_check)
      if (proof = transition_run&.progress&.dig("discovery_refresh"))
        details[:event_inventory]&.merge!(refresh_completed_at: proof["refresh_completed_at"], refreshed_list_count: proof.fetch("lists").size)
      end
      details[:event_sample] = transition_run.event_sample if transition_run&.event_sample
      if details.dig(:event_inventory, :status) == "active_event_scope" && representative_webpages.any?
        details[:validation_coverage] = {
          configuration: TransitionFingerprint.configuration(website),
          pages: representative_webpages.to_h { |page| [page.id.to_s, TransitionFingerprint.event_page(page)] }
        }
      end

      unless representative_webpages.present?
        return [:pending, details.merge(reason: "no_representative_webpages", representative_urls_checked: false)]
      end

      unless cache.present?
        return [:failed, details.merge(reason: "missing_cache")]
      end

      if representative_url_results.any? { |result| result[:fetch_status] == "failed" }
        failed_result = representative_url_results.find { |result| result[:fetch_status] == "failed" }
        return [:failed, details.merge(reason: failed_result[:fetch_reason] || "cache_health_failed")]
      end

      # Aggregate blockers across the whole sample before considering review or
      # unavailable legacy metadata on another URL.
      if representative_url_results.any? { |result| result[:comparison_status] == "failed" }
        return [:failed, details.merge(reason: "cache_compare_blocking_regression")]
      end
      if representative_url_results.any? { |result| result[:comparison_status] == "unknown" }
        return [:failed, details.merge(reason: "cache_compare_unknown")]
      end
      unavailable_legacy = %w[missing_config unreachable body_omitted]
      if representative_url_results.any? { |result| result[:comparison_status] == "missing" && !unavailable_legacy.include?(result[:legacy_lookup_status]) }
        return [:failed, details.merge(reason: "cache_compare_missing")]
      end
      unavailable_legacy.each do |lookup_status|
        if representative_url_results.any? { |result| result[:legacy_lookup_status] == lookup_status }
          return [:checked, details.merge(reason: "legacy_lookup_#{lookup_status}", comparison_performed: false)]
        end
      end
      if representative_url_results.any? { |result| result[:comparison_status] == "review" }
        return [:checked, details.merge(reason: "review_needed_difference")]
      end
      if representative_url_results.any? { |result| result[:comparison_status] == "metadata_only" }
        return [:checked, details.merge(reason: "metadata_only_difference")]
      end

      [:checked, details.merge(reason: "ok")]
    end

    def cache_or_seed_url(cache)
      cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
    end

    def fetch_failure_reason_from_result(result)
      return "missing_condenser_attempt" unless result.present?
      return "cached_response_rejected" if result.cache_hit == true
      return "empty_body" if truthy?(cache_signal(result.cache, :empty_body))
      return "captcha_detected" if captcha_result?(result)
      return missing_renderer_reason(result) if missing_renderer_reason(result).present?

      result.blocking_issue_key.presence ||
        cache_signal(result.cache, :primary_issue_key).presence ||
        cache_signal(result.cache, :network_status).presence ||
        "cache_health_failed"
    end

    def recorded_fetch_error(result)
      body = result.respond_to?(:body) ? result.body : nil
      error = body.is_a?(Array) ? body.find { |item| item.is_a?(Hash) } : (body if body.is_a?(Hash))
      error = result.fetch_error if result.respond_to?(:fetch_error) && result.fetch_error.present?
      detail = error.to_h.with_indifferent_access
      hints = result.respond_to?(:hints) ? Array(result.hints).grep(String) : []
      ([detail[:error_type], detail[:error]] + hints).compact.map(&:to_s).reject(&:blank?).uniq.join("; ").presence
    end

    def cache_signal(cache, key)
      return nil unless cache.present?

      signals = (cache.signals || {}).to_h
      return signals[key.to_s] if signals.key?(key.to_s)
      return signals[key.to_sym] if signals.key?(key.to_sym)

      nil
    end

    def truthy?(value)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    def record_missing_representatives(latest_cache, check_kind, transition_check)
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: check_kind,
        status: :pending,
        export_diff_status: check_kind == :export_diff ? "pending" : nil,
        details: scope_details(transition_check, []).merge(
          source: "transition_check",
          export_compared: check_kind == :export_diff ? false : nil,
          export_basis: check_kind == :export_diff ? "current export vs production-equivalent export" : nil,
          statements_refreshed_count: check_kind == :statement_delta ? 0 : nil,
          statements_failed_count: check_kind == :statement_delta ? 0 : nil,
          reason: "no_representative_webpages"
        ).compact
      )
    end

    def failure_details(reason, error)
      {
        source: "transition_check",
        reason: reason,
        error_class: error.class.name,
        error_message: error.message
      }
    end

    def scope_details(transition_check, representative_webpages)
      publishable_event_page_count = transition_check.publishable_event_page_count.to_i
      {
        representative_webpages: representative_webpages.map(&:url),
        representative_webpage_count: representative_webpages.count,
        candidate_webpage_count: transition_check.candidate_webpage_count,
        publishable_event_page_count: publishable_event_page_count,
        original_publishable_event_page_count: transition_check.respond_to?(:original_publishable_event_page_count) ? transition_check.original_publishable_event_page_count : publishable_event_page_count,
        transition_exclusions: transition_check.respond_to?(:transition_exclusions) ? Array(transition_check.transition_exclusions) : [],
        selected_candidate_tier_count: transition_check.selected_candidate_tier_count,
        selection_rule: transition_check.selection_rule,
        check_options: @check_options.to_h,
        dsl_contract_version: Dsl::Core::AlgorithmRunner::CONTRACT_VERSION,
        fetch_basis: "fresh_both",
        active_path_verification: @verify_active_path,
        fetch_attempted_webpage_count: Array(@representative_url_results).count { |row| row[:attempted_condenser_fetch] },
        sample_small: transition_check.selected_candidate_tier_count.to_i > representative_webpages.count
      }
    end

    def inventory_details(check)
      return unless check.respond_to?(:event_inventory) && (inventory = check.event_inventory)

      inventory.to_h.merge(valid_until: inventory.valid_until&.iso8601).compact
    end

    def representative_url_result_for(webpage, comparison_policy)
      cached = @representative_result_cache[webpage.url]
      return cached.merge(url: webpage.url, webpage_id: webpage.id) if cached.present?

      result = TransitionFetchSlot.call(uri: webpage.url, wait_allowed: -> { !comparison_stop_requested? }) do |wait_ms|
        fetch_page_pair(webpage, comparison_policy).merge(source_fetch_wait_ms: wait_ms)
      end
      @representative_result_cache[webpage.url] = result if result
      result || timed_out_representative_url_result(webpage)
    end

    def fetch_page_pair(webpage, comparison_policy)
      render_js = applicable_sources_for(webpage).any?(&:render_js?)
      if @verify_active_path
        resolution = FetchMode.rollout_resolution_object(website: website.reload)
        raise "Active serving path is not Condenser" unless website.distillator_mode == "active" && resolution.active_backend == :condenser
      end
      fetch_result = fetch_cache_store.fetch(
        uri: webpage.url,
        render_js: render_js,
        force_scrape: true,
        mode: @verify_active_path ? nil : "internal",
        website: website,
        log_context: {
          source: "transition_check",
          website_id: website.id,
          seedurl: website.seedurl
        }
      )
      @cancellation_check&.call
      comparison = cache_compare.call(
        uri: webpage.url,
        condenser_result: fetch_result,
        comparison_policy: comparison_policy,
        fresh_legacy: true,
        render_js: render_js,
        legacy_retry_budget: method(:remaining_fetch_budget)
      )

      build_representative_url_result(webpage, fetch_result, comparison)
    end

    def selected_sources_for(webpage)
      applicable_sources_for(webpage).select(&:selected?)
    end

    def applicable_sources_for(webpage)
      language = website.default_language
      key = [webpage.website_id, webpage.rdfs_class.name, webpage.language, language]
      @applicable_sources[key] ||= Statements::RefreshWebpageStatementsService.sources_for_webpage(webpage,
        default_language: language)
    end

    def build_representative_url_result(webpage, fetch_result, comparison)
      fetch_status = fetch_result.cache_hit != true && fetch_result.transport_success? && fetch_result.content_success? ? "passed" : "failed"
      active_path_failed = @require_native_path && (!fetch_result.respond_to?(:fetch_path) || fetch_result.fetch_path != "native")
      fetch_status = "failed" if active_path_failed
      cache = fetch_result.cache
      {
        url: webpage.url,
        webpage_id: webpage.id,
        cache: cache && CacheMetadata.new(cache.normalized_url, cache.primary_issue_key, cache.http_response_code),
        html_pair: (store_html_pair(comparison&.dig(:legacy_cache, :html), cache&.html) if fetch_status == "passed"),
        attempted_condenser_fetch: true,
        condenser_fetch_success: fetch_status == "passed",
        http_response_code: fetch_result.http_response_code.presence || fetch_result.cache&.http_response_code,
        cache_health_status: fetch_result.cache&.health_status,
        stored_html: fetch_result.cache&.html.present?,
        stored_body_bytes: fetch_result.cache&.body.to_s.bytesize,
        fetch_status: fetch_status,
        fetch_reason: active_path_failed ? (@verify_active_path ? "active_path_did_not_use_condenser" : "native_fetch_not_established") : (fetch_status == "failed" ? fetch_failure_reason_from_result(fetch_result) : "ok"),
        condenser_error: fetch_status == "failed" ? recorded_fetch_error(fetch_result) : nil,
        comparison_performed: comparison.present?,
        legacy_source: comparison&.dig(:legacy_source),
        legacy_lookup_status: comparison&.dig(:legacy_lookup_status),
        legacy_lookup_error: comparison&.dig(:legacy_lookup_error),
        legacy_fetch: comparison&.dig(:legacy_fetch),
        condenser_fetch: recorded_fetch_diagnostics(fetch_result),
        condenser_source: comparison&.dig(:condenser_source),
        compare_missing: comparison&.dig(:missing),
        compare_summary: comparison&.dig(:summary),
        comparison_status: comparison_status(comparison)
      }
    end

    def store_html_pair(legacy, condenser)
      return if legacy.blank? || condenser.blank?

      [legacy, condenser].map do |html|
        offset = @snapshot_file.pos
        @snapshot_file.write(html)
        [offset, html.bytesize, html.encoding]
      end
    end

    def read_html_pair(input)
      input[:html_pair]&.map do |offset, bytes, encoding|
        @snapshot_file.pread(bytes, offset).force_encoding(encoding)
      end
    end

    def recorded_fetch_diagnostics(result)
      signals = result.signals.to_h.with_indifferent_access
      matched = signals[:primary_issue_match].to_h.with_indifferent_access
      headers = result.respond_to?(:headers) ? result.headers : result.cache&.headers
      fetch_path = result.fetch_path if result.respond_to?(:fetch_path)
      cloudflare = Distillator::FetchService.cloudflare_response_headers(headers, signals: signals, fetch_path: fetch_path)
      {
        attempted_at: result.scrape_date || result.cache&.scrape_date, cache_hit: result.cache_hit,
        cloudflare: (cloudflare.merge(request_method: signals[:request_method]).compact if cloudflare.present?),
        fetch_path: fetch_path, fetch_backend: signals[:fetch_backend], render_js: signals[:use_phantomjs],
        active_path_verification: @verify_active_path,
        transport_success: result.transport_success?, content_success: result.content_success?,
        blocking_issue_key: result.blocking_issue_key,
        matched_rule: signals[:primary_issue_key],
        match: matched.slice(:source, :pattern, :snippet).transform_values { |value| value.to_s.first(300) }.presence
      }.compact
    end

    def collect_representative_url_results(representative_webpages, comparison_policy, offset: 0, total: representative_webpages.length)
      collected = []

      representative_webpages.each_with_index do |webpage, index|
        @cancellation_check&.call
        if timeout_budget_exceeded?
          return collected + representative_webpages.drop(index).map { |remaining| timed_out_representative_url_result(remaining) }
        end

        collected << representative_url_result_for(webpage, comparison_policy)
        record_page_progress("fetch", offset + index + 1, total)
      end

      collected
    end

    def comparison_status(comparison)
      return "not_performed" if comparison.blank?
      return "failed" if comparison.dig(:summary, :operational_failures).present?
      return "missing" if comparison.dig(:missing, :legacy) || comparison.dig(:missing, :condenser)
      return "failed" if comparison.dig(:summary, :blocking_regressions).present?
      return "review" if comparison.dig(:summary, :review_needed_diffs).present?
      return "unknown" if comparison.dig(:summary, :unknown_diffs).present?
      return "metadata_only" if comparison.dig(:summary, :metadata_only_diffs).present? || comparison.dig(:summary, :improvements).present?

      "passed"
    end

    def serializable_representative_url_result(result)
      result.except(:cache, :html_pair)
    end

    def representative_failed_layer(results)
      return "fetch" if results.any? { |result| result[:fetch_status] == "failed" }
      return "cache_compare" if results.any? { |result| result[:comparison_status] == "failed" }
      return "legacy_lookup" if results.any? { |result| %w[missing_config unreachable body_omitted].include?(result[:legacy_lookup_status]) }
      return "cache_compare" if results.any? { |result| %w[failed review unknown missing].include?(result[:comparison_status]) }

      nil
    end

    def representative_affected_url_count(results)
      return results.count { |result| result[:fetch_status] == "failed" } if representative_failed_layer(results) == "fetch"
      return results.count { |result| %w[missing_config unreachable body_omitted].include?(result[:legacy_lookup_status]) } if representative_failed_layer(results) == "legacy_lookup"
      return results.count { |result| %w[failed review unknown missing].include?(result[:comparison_status]) } if representative_failed_layer(results) == "cache_compare"

      0
    end

    def representative_export_results(representative_webpages, failed_fetch_results, status, reason)
      representative_webpages.map do |webpage|
        { url: webpage.url, status: status, reason: reason }
      end + failed_fetch_results.map do |result|
        { url: result[:url], status: "blocked_by_fetch", reason: result[:fetch_reason] }
      end
    end

    def partition_representative_webpages(representative_webpages, representative_url_results)
      results_by_url = representative_url_results.index_by { |result| result[:url] }
      fetched_webpages = representative_webpages.select { |webpage| results_by_url.fetch(webpage.url, {})[:fetch_status] != "failed" }
      failed_fetch_results = representative_url_results.select { |result| result[:fetch_status] == "failed" }
      [fetched_webpages, failed_fetch_results]
    end

    def pending_statement_timeout_record(latest_cache, transition_check, representative_webpages, fetched_webpages, failed_fetch_results)
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :statement_delta,
        status: :pending,
        statement_delta: 0,
        statement_count_delta_acceptable: nil,
        details: scope_details(transition_check, representative_webpages).merge(
          source: "paired_extraction",
          representative_url_statement_results: representative_statement_timeout_results(fetched_webpages, failed_fetch_results),
          statements_refreshed_count: 0,
          compared_webpage_count: 0,
          statements_failed_count: 0,
          failing_statement_ids: [],
          failing_statements: [],
          reason: "transition_check_timeout_budget_exceeded"
        )
      )
    end

    def pending_export_timeout_record(latest_cache, transition_check, representative_webpages, fetched_webpages, failed_fetch_results)
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: :pending,
        export_diff_checked: false,
        export_diff_status: "pending",
        details: scope_details(transition_check, representative_webpages).merge(
          source: "export_comparison",
          export_compared: false,
          export_basis: "current export vs production-equivalent export",
          representative_url_export_results: representative_export_timeout_results(fetched_webpages, failed_fetch_results),
          reason: "transition_check_timeout_budget_exceeded"
        )
      )
    end

    def representative_statement_timeout_results(fetched_webpages, failed_fetch_results)
      fetched_webpages.map do |webpage|
        {
          url: webpage.url,
          status: "inconclusive",
          reason: "transition_check_timeout_budget_exceeded"
        }
      end + failed_fetch_results.map do |result|
        {
          url: result[:url],
          status: "blocked_by_fetch",
          reason: result[:fetch_reason]
        }
      end
    end

    def representative_export_timeout_results(fetched_webpages, failed_fetch_results)
      fetched_webpages.map do |webpage|
        {
          url: webpage.url,
          status: "inconclusive",
          reason: "transition_check_timeout_budget_exceeded"
        }
      end + failed_fetch_results.map do |result|
        {
          url: result[:url],
          status: "blocked_by_fetch",
          reason: result[:fetch_reason]
        }
      end
    end

    def timed_out_representative_url_result(webpage)
      {
        url: webpage.url,
        webpage_id: webpage.id,
        cache: nil,
        attempted_condenser_fetch: false,
        condenser_fetch_success: false,
        http_response_code: nil,
        cache_health_status: nil,
        stored_html: false,
        stored_body_bytes: 0,
        fetch_status: "failed",
        fetch_reason: "transition_check_timeout_budget_exceeded",
        comparison_performed: false,
        legacy_source: nil,
        legacy_lookup_status: nil,
        legacy_lookup_error: nil,
        condenser_source: nil,
        compare_missing: nil,
        compare_summary: nil,
        comparison_status: "not_performed"
      }
    end

    def timeout_budget_exceeded?
      remaining = remaining_time_budget
      !remaining.nil? && remaining <= 0
    end

    def remaining_fetch_budget
      @cancellation_check&.call
      remaining_time_budget
    end

    def remaining_time_budget
      return unless budget_seconds.present?

      [budget_seconds.to_f - timeout_guard_seconds.to_f - (monotonic_now - @started_at), 0].max
    end

    def budget_seconds
      return @budget_seconds unless @budget_seconds.nil?
      return unless transition_run

      @run_budget_seconds ||= [transition_run.requested_at + Distillator::TransitionRun::LEASE - Time.current - 60, 0].max
    end

    def monotonic_now
      @clock.call.to_f
    end

    def captcha_result?(result)
      issue_key = result.blocking_issue_key.presence || cache_signal(result.cache, :primary_issue_key).presence
      return true if issue_key.to_s == "system_captcha"

      Array(result.respond_to?(:hints) ? result.hints : nil).map(&:to_s).any? { |hint| hint.include?("captcha") }
    end

    def missing_renderer_reason(result)
      return nil unless truthy?(cache_signal(result.cache, :renderer_unavailable))

      if truthy?(cache_signal(result.cache, :use_phantomjs)) && ENV["PHANTOMJS_API_KEY"].blank?
        "phantomjs_api_key_missing"
      else
        "renderer_unavailable"
      end
    end
  end
end
