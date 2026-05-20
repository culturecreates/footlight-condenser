require "will_paginate/collection"

module Distillator
  class ShadowReportQuery
    FILTER_KEYS = %i[status recommendation health_severity primary_issue_key term cohort mode promotable].freeze
    SORT_COLUMNS = %w[website status recommendation latest_attempt latest_successful_refresh issue_key].freeze
    DEFAULT_SORT = "website".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100
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
      name
      scrape_date
      successful_refresh
      http_response_code
      headers
      signals
      hints
      final_url
      redirect_chain
      created_at
      updated_at
      health_status
      health_severity
      health_reasons
      html_bytes
      body_bytes
      redirected
      network_status
      content_type
      hint_keys
      primary_issue_key
      primary_issue_error_code
      primary_issue_label
      primary_issue_severity
      primary_issue_category
      issue_keys
      issue_hints
      delete_candidate
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
      normalized_per_page = per_page.to_i.positive? ? per_page.to_i : DEFAULT_PER_PAGE
      @per_page = [normalized_per_page, MAX_PER_PAGE].min
    end

    def call
      summaries = filtered_summaries
      paginated = paginate_rows(summaries)

      Result.new(
        records: paginated.to_a,
        all_records: summaries,
        global_records: all_summaries,
        page: paginated.current_page,
        per_page: paginated.per_page,
        total_count: paginated.total_entries,
        total_pages: paginated.total_pages
      )
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def filtered_summaries
      @filtered_summaries ||= begin
        rows = all_summaries.select { |summary| include_summary?(summary) }
        rows = rows.sort_by { |summary| sortable_value(summary) }
        rows.reverse! if direction == "desc"
        rows
      end
    end

    def all_summaries
      @all_summaries ||= websites.map do |website|
        Distillator::ShadowSiteSummary.call(
          website: website,
          cache: latest_caches_by_website_id[website.id]
        )
      end
    end

    def websites
      @websites ||= Website.where(distillator_mode: Website::DISTILLATOR_MODES).includes(:webpages).order(:name).to_a
    end

    def latest_caches_by_website_id
      @latest_caches_by_website_id ||= begin
        lookup = {}
        latest_caches.each do |cache|
          website = matched_website_for_cache(cache)
          next unless website
          next if lookup.key?(website.id)

          lookup[website.id] = cache
        end
        lookup
      end
    end

    def latest_caches
      @latest_caches ||= begin
        urls = candidate_urls
        keys = candidate_uri_keys
        return [] if urls.empty? && keys.empty?

        Distillator::FetchCache
          .select(CACHE_COLUMNS.map { |column| "distillator_fetch_caches.#{column}" })
          .where("normalized_url IN (:urls) OR final_url IN (:urls) OR uri_key IN (:keys)", urls: urls.presence || [""], keys: keys.presence || [""])
          .order(Arel.sql("COALESCE(distillator_fetch_caches.scrape_date, distillator_fetch_caches.updated_at) DESC, distillator_fetch_caches.id DESC"))
          .to_a
      end
    end

    def matched_website_for_cache(cache)
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

    def paginate_rows(rows)
      WillPaginate::Collection.create(page, per_page, rows.length) do |pager|
        pager.replace(rows[pager.offset, pager.per_page] || [])
      end
    end

    def candidate_urls
      @candidate_urls ||= websites.flat_map do |website|
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

    def candidate_uri_keys
      @candidate_uri_keys ||= websites.flat_map do |website|
        website.webpages.filter_map do |webpage|
          Distillator::WringerUrlKey.call(webpage.url).uri_key
        rescue StandardError
          nil
        end
      end.uniq
    end

    class << self
      def latest_cache_for_website(website)
        website_record = website.is_a?(Website) ? website : Website.find(website)
        query = new(filters: {}, sort: DEFAULT_SORT, direction: DEFAULT_DIRECTION, page: 1, per_page: 1)
        query.send(:latest_caches).find do |cache|
          Distillator::CacheWebsiteMatcher.call(cache: cache, websites: [website_record]).website.present?
        end
      end
    end
  end
end
