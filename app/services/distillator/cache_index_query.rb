module Distillator
  class CacheIndexQuery
    DB_SORT_COLUMNS = {
      "id" => :id,
      "updated_at" => :updated_at,
      "scrape_date" => :scrape_date,
      "successful_refresh" => :successful_refresh,
      "http_response_code" => :http_response_code,
      "name" => :name,
      "normalized_url" => :normalized_url,
      "uri_key" => :uri_key,
      "html_bytes" => :html_bytes,
      "body_bytes" => :body_bytes
    }.freeze

    Result = Struct.new(:records, :total_count, :page, :per_page, :total_pages, :summary_scope, keyword_init: true)

    def self.call(filters:, sort:, direction:, page:, per_page:)
      new(filters: filters, sort: sort, direction: direction, page: page, per_page: per_page).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:)
      @filters = (filters || {}).with_indifferent_access
      @sort = sort.to_s
      @direction = direction.to_s
      @page = page.to_i
      @per_page = per_page.to_i
    end

    def call
      relation = apply_sql_filters(Distillator::FetchCache.all)
      build_sql_result(relation)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def build_sql_result(relation)
      ordered = relation.order(db_sort_column => direction.to_sym)
      total_count = ordered.count
      total_pages = [((total_count.to_f / per_page).ceil), 1].max
      records = ordered.limit(per_page).offset((page - 1) * per_page)

      Result.new(
        records: records,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages,
        summary_scope: relation
      )
    end

    def apply_sql_filters(relation)
      filtered = relation

      if filters[:term].present?
        term = "%#{filters[:term].downcase}%"
        filtered = filtered.where(
          "LOWER(uri_key) LIKE :term OR LOWER(normalized_url) LIKE :term OR LOWER(COALESCE(name, '')) LIKE :term",
          term: term
        )
      end

      if normalized_http_response_code_filter.present?
        filtered = filtered.where(http_response_code: normalized_http_response_code_filter)
      end

      case filters[:has_html]
      when "true"
        filtered = filtered.where.not(html: [nil, ""])
      when "false"
        filtered = filtered.where(html: [nil, ""])
      end

      if filters[:network_status].present?
        filtered =
          if materialized_field_available?("network_status")
            filtered.where(network_status: filters[:network_status])
          else
            filtered.where("signals ->> 'network_status' = ?", filters[:network_status])
          end
      end

      if filters[:health].present? && materialized_field_available?("health_status")
        filtered = filtered.where(health_status: filters[:health])
      end

      if filters[:status_group].present?
        filtered = apply_status_group_filter(filtered)
      end

      if filters[:content_type].present?
        filtered =
          if materialized_field_available?("content_type")
            filtered.where(content_type: filters[:content_type])
          else
            filtered.where("COALESCE(signals ->> 'content_type', 'unknown') = ?", filters[:content_type])
          end
      end

      if filters[:hint].present?
        filtered = filtered.where("LOWER(COALESCE(hint_keys::text, hints::text, '')) LIKE ?", "%#{filters[:hint].downcase}%")
      end

      if filters[:redirected].present?
        filtered = apply_redirected_filter(filtered)
      end

      if filters[:last_attempt].present?
        filtered = apply_time_window_filter(filtered, column: :scrape_date, value: filters[:last_attempt])
      end

      if filters[:last_success].present?
        filtered = apply_time_window_filter(filtered, column: :successful_refresh, value: filters[:last_success])
      end

      filtered
    end

    def apply_status_group_filter(relation)
      case filters[:status_group]
      when "2xx"
        relation.where(http_response_code: 200..299)
      when "3xx"
        relation.where(http_response_code: 300..399)
      when "4xx"
        relation.where(http_response_code: 400..499)
      when "5xx"
        relation.where(http_response_code: 500..599)
      when "nil"
        relation.where(http_response_code: nil)
      else
        relation
      end
    end

    def apply_redirected_filter(relation)
      redirected = ActiveModel::Type::Boolean.new.cast(filters[:redirected])
      predicate =
        if materialized_field_available?("redirected")
          "redirected = TRUE"
        else
          "jsonb_array_length(redirect_chain) > 0 OR (final_url IS NOT NULL AND final_url <> normalized_url)"
        end

      redirected ? relation.where(predicate) : relation.where("NOT (#{predicate})")
    end

    def apply_time_window_filter(relation, column:, value:)
      case value
      when "never"
        relation.where(column => nil)
      when "last_hour"
        relation.where(column => 1.hour.ago..)
      when "last_24h"
        relation.where(column => 24.hours.ago..)
      when "last_7d"
        relation.where(column => 7.days.ago..)
      when "older_7d"
        relation.where.not(column => nil).where(column => ...7.days.ago)
      else
        relation
      end
    end

    def db_sort_column
      DB_SORT_COLUMNS.fetch(sort, :updated_at)
    end

    def normalized_http_response_code_filter
      value = filters[:http_response_code].to_s.strip
      return nil if value.blank?
      return nil unless value.match?(/\A\d+\z/)

      value.to_i
    end

    def materialized_field_available?(column_name)
      Distillator::FetchCache.column_names.include?(column_name)
    end
  end
end
