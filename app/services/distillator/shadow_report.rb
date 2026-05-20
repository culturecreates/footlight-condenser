module Distillator
  class ShadowReport
    Result = Struct.new(:rows, :summary_counts, :global_summary_counts, :dashboard_counts, :blocker_counts, :page, :per_page, :total_count, :total_pages, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:)
      @filters = filters
      @sort = sort
      @direction = direction
      @page = page
      @per_page = per_page
    end

    def call
      query = Distillator::ShadowReportQuery.call(
        filters: @filters,
        sort: @sort,
        direction: @direction,
        page: @page,
        per_page: @per_page
      )

      Result.new(
        rows: query.records,
        summary_counts: summary_counts(query.all_records),
        global_summary_counts: summary_counts(query.global_records),
        dashboard_counts: dashboard_counts(query.global_records),
        blocker_counts: blocker_counts(query.all_records),
        page: query.page,
        per_page: query.per_page,
        total_count: query.total_count,
        total_pages: query.total_pages
      )
    end

    private

    def summary_counts(rows)
      rows.each_with_object(
        {
          total: rows.length,
          ready: 0,
          review: 0,
          blocked: 0,
          not_checked: 0,
          lavitrine_total: 0,
          lavitrine_ready: 0,
          lavitrine_review: 0,
          lavitrine_blocked: 0,
          lavitrine_not_checked: 0
        }
      ) do |row, counts|
        counts[row.status] += 1 if counts.key?(row.status)
        next unless row.cohort_key == Distillator::Cohorts::LavitrinePipeline.key

        counts[:lavitrine_total] += 1
        counts[:"lavitrine_#{row.status}"] += 1
      end
    end

    def dashboard_counts(rows)
      mode_counts = Website.group(:distillator_mode).count

      {
        legacy_sites: mode_counts.fetch("legacy", 0),
        shadow_sites: mode_counts.fetch("shadow", 0),
        active_sites: mode_counts.fetch("active", 0),
        priority_sites: rows.count { |row| row.priority },
        blocked_sites: rows.count { |row| row.status == :blocked },
        promotable_sites: rows.count(&:promotable)
      }
    end

    def blocker_counts(rows)
      rows.each_with_object(
        {
          failed_fetch: 0,
          missing_statement_evidence: 0,
          missing_export_evidence: 0,
          stale_evidence: 0,
          redirect_cache_health_review: 0
        }
      ) do |row, counts|
        messages = Array(row.blockers) + Array(row.warnings)

        counts[:failed_fetch] += 1 if messages.any? { |message| message.include?("fetch check failed") }
        counts[:missing_statement_evidence] += 1 if messages.any? { |message| message.include?("statements check is missing") }
        counts[:missing_export_evidence] += 1 if messages.any? { |message| message.include?("export check is missing") }
        counts[:stale_evidence] += 1 if messages.any? { |message| message.include?("check is stale") || message.include?("latest successful refresh is stale") }
        counts[:redirect_cache_health_review] += 1 if messages.any? { |message| message.include?("fetch result redirected") }
      end
    end
  end
end
