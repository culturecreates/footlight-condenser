require "will_paginate/collection"

module Distillator
  class ShadowReportQuery
    FILTER_KEYS = %i[status recommendation health_severity primary_issue_key term cohort mode promotable].freeze
    SORT_COLUMNS = %w[website status recommendation latest_attempt latest_successful_refresh issue_key].freeze
    DEFAULT_SORT = "website".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    DEFAULT_PER_PAGE = DEFAULT_LIMIT
    MAX_PER_PAGE = MAX_LIMIT
    RECOMMENDATION_ORDER = {
      "blocked" => 0,
      "review" => 1,
      "ready" => 2,
      "not_checked" => 3,
      "unknown" => 3
    }.freeze

    CACHE_COLUMNS = %w[
      id
      uri_key
      normalized_url
      http_response_code
      scrape_date
      successful_refresh
      signals
      final_url
      health_status
      health_severity
      redirected
      network_status
      primary_issue_key
      primary_issue_label
      primary_issue_severity
    ].freeze

    Result = Struct.new(:records, :all_records, :global_records, :page, :per_page, :total_count, :total_pages, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:)
      @filters = filters.to_h.symbolize_keys
      @sort = SORT_COLUMNS.include?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
      @page = page.to_i.positive? ? page.to_i : 1
      normalized_per_page = per_page.to_i.positive? ? per_page.to_i : DEFAULT_LIMIT
      @per_page = [normalized_per_page, MAX_LIMIT].min
    end

    def call
      return default_result if default_report?

      summaries = filtered_summaries
      paginated = paginate_rows(summaries, total_count: summaries.length)

      Result.new(
        records: paginated.to_a,
        all_records: summaries,
        global_records: summaries,
        page: paginated.current_page,
        per_page: paginated.per_page,
        total_count: paginated.total_entries,
        total_pages: paginated.total_pages
      )
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def default_result
      scope = default_shadow_scope
      rows = build_summaries(paginated_websites(scope))
      total_count = scope.count
      total_pages = (total_count.to_f / per_page).ceil
      paginated = WillPaginate::Collection.create(page, per_page, total_count) do |pager|
        pager.replace(rows)
      end

      Result.new(
        records: paginated.to_a,
        all_records: rows,
        global_records: rows,
        page: paginated.current_page,
        per_page: paginated.per_page,
        total_count: paginated.total_entries,
        total_pages: total_pages
      )
    end

    def filtered_summaries
      @filtered_summaries ||= begin
        rows = build_summaries(websites).select { |summary| include_summary?(summary) }
        rows = rows.sort_by { |summary| sortable_value(summary) }
        rows.reverse! if direction == "desc"
        rows
      end
    end

    def build_summaries(websites)
      return [] if websites.empty?

      evidence_by_website_id = Distillator::TransitionEvidence.latest_for_website_ids(websites.map(&:id))
      latest_caches_by_website_id = latest_caches_by_website_id_for(websites)

      websites.map do |website|
        Distillator::ShadowSiteSummary.call(
          website: website,
          cache: latest_caches_by_website_id[website.id],
          evidence_by_kind: evidence_by_website_id[website.id]
        )
      end
    end

    def websites
      @websites ||= website_scope.includes(:webpages).order(:name).to_a
    end

    def latest_caches_by_website_id_for(websites)
      lookup = {}

      latest_caches_for(websites).each do |cache|
        website = matched_website_for_cache(cache, websites)
        next unless website
        next if lookup.key?(website.id)

        lookup[website.id] = cache
      end

      lookup
    end

    def latest_caches_for(websites)
      urls = candidate_urls(websites)
      keys = candidate_uri_keys(websites)
      return [] if urls.empty? && keys.empty?

      Distillator::FetchCache
        .select(CACHE_COLUMNS.map { |column| "distillator_fetch_caches.#{column}" })
        .where("normalized_url IN (:urls) OR final_url IN (:urls) OR uri_key IN (:keys)", urls: urls.presence || [""], keys: keys.presence || [""])
        .order(Arel.sql("COALESCE(distillator_fetch_caches.scrape_date, distillator_fetch_caches.updated_at) DESC, distillator_fetch_caches.id DESC"))
        .to_a
    end

    def matched_website_for_cache(cache, websites)
      result = Distillator::CacheWebsiteMatcher.call(cache: cache, websites: websites)
      result.website
    end

    def include_summary?(summary)
      status_match?(summary) &&
        mode_match?(summary) &&
        promotable_match?(summary) &&
        health_severity_match?(summary) &&
        primary_issue_key_match?(summary) &&
        cohort_match?(summary) &&
        term_match?(summary)
    end

    def mode_match?(summary)
      return true if filters[:mode].blank?

      summary.website.distillator_mode.to_s == filters[:mode].to_s
    end

    def status_match?(summary)
      requested = filters[:status].presence || filters[:recommendation].presence
      return true if requested.blank?

      summary.status.to_s == requested.to_s
    end

    def promotable_match?(summary)
      requested = filters[:promotable].to_s
      return true if requested.blank?

      case requested
      when "yes"
        summary.promotable
      when "no"
        !summary.promotable
      else
        true
      end
    end

    def health_severity_match?(summary)
      return true if filters[:health_severity].blank?

      summary.health_severity.to_s == filters[:health_severity].to_s
    end

    def primary_issue_key_match?(summary)
      return true if filters[:primary_issue_key].blank?

      summary.issue_key.to_s == filters[:primary_issue_key].to_s
    end

    def term_match?(summary)
      return true if filters[:term].blank?

      haystack = [summary.website.name, summary.website.seedurl, summary.cohort_label].compact.join(" ").downcase
      haystack.include?(filters[:term].to_s.downcase)
    end

    def cohort_match?(summary)
      return true if filters[:cohort].blank?

      case filters[:cohort].to_s
      when "other"
        summary.cohort_key.blank?
      else
        summary.cohort_key.to_s == filters[:cohort].to_s
      end
    end

    def sortable_value(summary)
      case sort
      when "status", "recommendation"
        RECOMMENDATION_ORDER.fetch(summary.status.to_s, 99)
      when "latest_attempt"
        summary.latest_refresh || Time.at(0)
      when "latest_successful_refresh"
        summary.latest_successful_refresh || Time.at(0)
      when "issue_key"
        summary.issue_key.to_s.downcase
      else
        summary.website.name.to_s.downcase
      end
    end

    def paginate_rows(rows, total_count:)
      WillPaginate::Collection.create(page, per_page, total_count) do |pager|
        pager.replace(rows[pager.offset, pager.per_page] || [])
      end
    end

    def candidate_urls(websites)
      websites.flat_map do |website|
        website.webpages.flat_map do |webpage|
          url = webpage.url.to_s
          next [] if url.blank?

          compact_urls = [url, url.split("#").first]
          if url.end_with?("/")
            compact_urls << url.chomp("/")
          else
            compact_urls << "#{url}/"
          end
          compact_urls.uniq
        end
      end.uniq
    end

    def candidate_uri_keys(websites)
      websites.flat_map do |website|
        website.webpages.filter_map do |webpage|
          Distillator::WringerUrlKey.call(webpage.url).uri_key
        rescue StandardError
          nil
        end
      end.uniq
    end

    def website_scope
      Website.where(distillator_mode: filters[:mode].presence || "shadow")
    end

    def default_shadow_scope
      @default_shadow_scope ||= Website.where(distillator_mode: "shadow").order(:name)
    end

    def paginated_websites(scope)
      scope.offset((page - 1) * per_page).limit(per_page).includes(:webpages).to_a
    end

    def default_report?
      return false unless filters.except(:mode).compact_blank.empty?
      return false unless filters[:mode].blank? || filters[:mode].to_s == "shadow"
      return false unless sort == DEFAULT_SORT
      return false unless direction == DEFAULT_DIRECTION

      true
    end

    class << self
      def latest_cache_for_website(website)
        website_record = website.is_a?(Website) ? website : Website.find(website)
        query = new(
          filters: { mode: website_record.distillator_mode },
          sort: DEFAULT_SORT,
          direction: DEFAULT_DIRECTION,
          page: 1,
          per_page: 1
        )

        query.send(:latest_caches_for, [website_record]).find do |cache|
          Distillator::CacheWebsiteMatcher.call(cache: cache, websites: [website_record]).website.present?
        end
      end
    end
  end
end
