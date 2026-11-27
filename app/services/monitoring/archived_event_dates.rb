module Monitoring
  class ArchivedEventDates
    # Only execute steps that read the supplied HTML or set its time zone.
    READ_STEPS = (Dsl::Core::AlgorithmRunner::SNAPSHOT_READ_ONLY_STEPS - ["manual"]).freeze
    Result = Struct.new(:date, :source_id, :reason, keyword_init: true)

    def self.call(page, as_of: Time.current)
      sources = Statements::RefreshWebpageStatementsService.sources_for_webpage(page, default_language: page.website.default_language)
      dates = sources.select { |source| source.selected? && source.property.label == "Dates" }
      overrides = page.statements.where(source_id: dates.map(&:id), selected_individual: true).pluck(:source_id, :manual)
      dates = dates.select { |source| overrides.any? { |id, _| id == source.id } } if overrides.any?
      return Result.new(reason: "ambiguous_dates_source") unless dates.one?

      source = dates.first
      if overrides.any? { |id, manual| id == source.id && manual } || !%w[xsd:date xsd:dateTime].include?(source.property.value_datatype)
        return Result.new(reason: "unsupported_dates_source")
      end

      steps = Dsl::LibraryExpander.call(source.algorithm_value.to_s).fetch(:steps)
      prefixes = steps.map { |step| step.partition("=").first }
      if (prefixes - ["time_zone"]).empty? || (prefixes - READ_STEPS).any?
        return Result.new(reason: "dates_extraction_requires_other_steps")
      end

      html = Distillator::TransitionFetchSlot.call(uri: page.url) { fresh_html(page, render_js: sources.any?(&:render_js?)) }
      return Result.new(reason: "fresh_event_page_unavailable") if html.blank?

      runner = Dsl::Core::AlgorithmRunner.new(url: page.url, tracer: Dsl::Tracing::NullTracer.new)
      raw = runner.run(steps.join(";"), snapshot_html: html)
      return Result.new(reason: "dates_extraction_failed") if runner.abort_structure?(raw)

      # Relative or yearless dates can be rolled into the current year by the
      # normal formatter. They are weak evidence for a reactivated event.
      raw = Array(raw).grep(String).select { |value| value.start_with?("time_zone:") || value.match?(/\b\d{4}\b/) }
      value = Time.use_zone(Time.zone) { ApplicationController.helpers.format_datatype(raw, source.property, page) }
      date = Array(value).filter_map { |entry| parse_date(entry) }.select { |entry| entry > as_of }.max
      Result.new(date: date, source_id: source.id, reason: ("no_explicit_future_date" unless date))
    rescue StandardError => error
      Result.new(reason: error.class.name)
    end

    def self.fresh_html(page, render_js:)
      url = page.url
      return unless Distillator::FetchGuard.check_url(url).allowed?

      active = Distillator::FetchMode.rollout_resolution_object(website: page.website).active_backend == :condenser
      if active
        result = Distillator::FetchService.fetch_result(url: url, render_js: render_js, website: page.website)
        signals = result.dig(:wringer, :signals).to_h.with_indifferent_access
        if result[:fetch_path] == "native" && result[:status] == :ok && signals[:transport_success] && signals[:content_success]
          return result[:body] if same_page?(url, result[:final_url])
        end
      else
        result = Distillator::FreshWringerSnapshot.call(uri: url, render_js: render_js)
        final_url = result.dig(:payload, "final_url") || result.dig(:payload, "signals", "final_url")
        if result[:status] == "ok" && same_page?(url, final_url)
          return result.dig(:payload, "html")
        end
      end
      nil
    end

    def self.same_page?(url, final_url)
      final_url.blank? || Distillator::WringerUrlKey.call(final_url).normalized_url == Distillator::WringerUrlKey.call(url).normalized_url
    end

    def self.parse_date(entry)
      Time.zone.iso8601(entry.to_s)
    rescue ArgumentError
      nil
    end

    private_class_method :fresh_html, :same_page?, :parse_date
  end
end
