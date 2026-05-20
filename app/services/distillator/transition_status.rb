module Distillator
  class TransitionStatus
    CHECK_RESULTS = %i[passed failed missing stale].freeze
    STATUSES = %i[ready review blocked not_checked].freeze

    Result = Struct.new(
      :status,
      :fetch,
      :statements,
      :export,
      :blockers,
      :warnings,
      :last_checked,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(website:, cache: nil, evidence_by_kind: nil, now: Time.current)
      @website = website
      @cache = cache
      @evidence_by_kind = evidence_by_kind
      @now = now
    end

    def call
      Result.new(
        status: overall_status,
        fetch: fetch_status,
        statements: statements_status,
        export: export_status,
        blockers: blockers,
        warnings: warnings,
        last_checked: last_checked
      )
    end

    private

    attr_reader :website, :cache, :now

    def overall_status
      return :not_checked unless cache.present? || any_evidence_present?
      return :blocked if blockers.any?
      return :review if warnings.any?

      :ready
    end

    def blockers
      reasons = []
      reasons << "Cannot activate yet: fetch check failed." if fetch_status == :failed
      reasons << "Cannot activate yet: fetch check is stale." if fetch_status == :stale && lavitrine_pipeline?
      reasons << "Cannot activate yet: statements check failed." if statements_status == :failed
      reasons << "Cannot activate yet: statements check is missing." if lavitrine_pipeline? && statements_status == :missing
      reasons << "Cannot activate yet: statements check is stale." if lavitrine_pipeline? && statements_status == :stale
      reasons << "Cannot activate yet: export check failed." if export_status == :failed
      reasons << "Cannot activate yet: export check is missing." if lavitrine_pipeline? && export_status == :missing
      reasons << "Cannot activate yet: export check is stale." if lavitrine_pipeline? && export_status == :stale
      reasons.uniq
    end

    def warnings
      reasons = []
      reasons << "Needs review: fetch check is stale." if fetch_status == :stale && !lavitrine_pipeline?
      reasons << "Needs review: statements check is missing." if !lavitrine_pipeline? && statements_status == :missing
      reasons << "Needs review: statements check is stale." if !lavitrine_pipeline? && statements_status == :stale
      reasons << "Needs review: export check is missing." if !lavitrine_pipeline? && export_status == :missing
      reasons << "Needs review: export check is stale." if !lavitrine_pipeline? && export_status == :stale
      reasons << "Needs review: export check is stale." if export_status == :stale && export_diff_evidence&.export_diff_accepted?
      reasons << "Needs review: fetch result redirected." if redirect_changed?
      reasons << "Needs review: latest successful refresh is stale." if stale_successful_refresh?
      reasons.uniq
    end

    def fetch_status
      return :missing unless cache.present?
      return :failed if fetch_failed?
      return :stale if fetch_evidence_stale?

      :passed
    end

    def statements_status
      evidence = statement_delta_evidence
      return :missing if lavitrine_pipeline? && !evidence.present?
      return signal_status("statement_count_delta_acceptable") unless evidence.present?
      return :missing if evidence.status.to_s == "pending"
      return :failed if evidence.status.to_s.in?(%w[failed blocked rejected]) || evidence.acceptable_statement_delta? == false
      return :stale if evidence.checked_at < now - evidence_stale_after
      return :passed if evidence.acceptable_statement_delta?

      :missing
    end

    def export_status
      evidence = export_diff_evidence
      return :missing if lavitrine_pipeline? && !evidence.present?
      return export_status_from_cache unless evidence.present?
      return :missing if evidence.status.to_s == "pending"
      return :failed if evidence.status.to_s.in?(%w[failed blocked rejected]) || explicit_false?(evidence.export_diff_checked)
      return :stale if export_evidence_stale?(evidence)
      return :passed if evidence.export_diff_satisfied?

      :missing
    end

    def signal_status(signal_key)
      value = signal(signal_key)
      return :missing if value.nil? || value.to_s == ""
      return :failed if explicit_false?(value)

      :passed
    end

    def export_status_from_cache
      return :missing unless cache.present?

      status = signal("export_diff_status").to_s
      checked = signal("export_diff_checked")
      accepted = signal("export_diff_accepted")
      return :failed if %w[failed blocked rejected].include?(status)
      return :passed if truthy?(checked) || truthy?(accepted) || %w[checked accepted].include?(status)

      :missing
    end

    def fetch_failed?
      latest_attempt_failed? || transport_failed? || content_failed? || blocking_issue? || last_good_preserved_failure?
    end

    def latest_attempt_failed?
      %w[blocked network_failed attempt_failed empty_body preserved_after_failure].include?(cache.health_status.to_s)
    end

    def transport_failed?
      explicit_false?(signal("transport_success")) || cache.network_status.to_s == "failed"
    end

    def content_failed?
      explicit_false?(signal("content_success"))
    end

    def blocking_issue?
      cache.primary_issue_severity.to_s.in?(%w[blocked failed])
    end

    def last_good_preserved_failure?
      truthy?(signal("last_good_preserved_failure"))
    end

    def fetch_evidence_stale?
      return false unless cache&.successful_refresh.present?

      cache.successful_refresh < now - evidence_stale_after
    end

    def stale_successful_refresh?
      fetch_evidence_stale?
    end

    def redirect_changed?
      return false unless cache.present?

      cache.redirected == true ||
        (cache.final_url.present? && cache.final_url.to_s != cache.normalized_url.to_s)
    end

    def export_evidence_stale?(evidence)
      threshold = evidence.export_diff_accepted? ? Distillator::PromotionReadiness::EXPORT_DIFF_STALE_AFTER : evidence_stale_after
      evidence.checked_at < now - threshold
    end

    def evidence_stale_after
      lavitrine_pipeline? ? Distillator::PromotionReadiness::LAVITRINE_EVIDENCE_STALE_AFTER : Distillator::PromotionReadiness::EVIDENCE_STALE_AFTER
    end

    def last_checked
      times = [cache&.scrape_date, cache&.successful_refresh]
      times.concat(evidence_by_kind.values.compact.map(&:checked_at))
      times.compact.max
    end

    def any_evidence_present?
      evidence_by_kind.values.any?(&:present?)
    end

    def evidence_by_kind
      @evidence_by_kind ||= website.respond_to?(:latest_transition_evidences_by_kind) ? website.latest_transition_evidences_by_kind : {}
    end

    def statement_delta_evidence
      evidence_by_kind["statement_delta"]
    end

    def export_diff_evidence
      evidence_by_kind["export_diff"]
    end

    def lavitrine_pipeline?
      website.respond_to?(:lavitrine_pipeline?) && website.lavitrine_pipeline?
    end

    def signal(key)
      return nil unless cache.present?

      signals = (cache.signals || {}).to_h
      return signals[key.to_s] if signals.key?(key.to_s)
      return signals[key.to_sym] if signals.key?(key.to_sym)

      nil
    end

    def truthy?(value)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    def explicit_false?(value)
      value == false || value.to_s == "false" || value.to_s == "0"
    end
  end
end
