require "will_paginate/collection"

module Events
  class IndexQuery
    FILTER_KEYS = %i[seedurl startDate endDate term].freeze
    DEFAULT_SORT = "archive_date".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = %w[title archive_date date rdf_uri].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:)
      @filters = filters.to_h.symbolize_keys
      @sort = SORT_COLUMNS.include?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
      @page = page.to_i
      @per_page = per_page.to_i
    end

    def call
      rows = website_statements_by_event.map do |rdf_uri, data|
        title = data.dig("title", :cache) || data.dig("title_fr", :cache) || data.dig("title_en", :cache)
        title = "Error" if title.blank? || title.to_s.include?("error:")
        {
          rdf_uri: rdf_uri,
          title: title.to_s,
          date: parse_date(data.dig("dates", :cache)),
          archive_date: data.dig(:archive_date, :cache),
          photo: data.dig("photo", :cache),
          statements_status: {
            to_review: data.any? { |_a, b| b.flatten.include?("initial") },
            updated: data.any? { |_a, b| b.flatten.include?("updated") },
            problem: data.any? { |_a, b| b.flatten.include?("problem") },
            publishable: publishable?(data)
          }
        }
      end
      rows = filter_term(rows)
      rows = rows.sort_by { |row| sortable_value(row[sort]) }
      rows.reverse! if direction == "desc"
      paginate_rows(rows)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def website_statements_by_event
      statements = Statement.joins(:webpage, source: :website)
                            .includes(:webpage, source: [:property, :website])
                            .where(websites: { seedurl: filters[:seedurl] }, webpages: { archive_date: time_span, rdfs_class_id: RdfsClass.where(name: "Event") })
                            .where(selected_individual: true)

      statements.each_with_object(Hash.new { |h, k| h[k] = {} }) do |statement, grouped|
        property_label = make_key(statement.source.property.label, statement.source.language)
        if grouped[statement.webpage.rdf_uri][property_label].present?
          grouped[statement.webpage.rdf_uri].merge!(property_label => { cache: statement.cache, status: "problem", selected_individual: statement.selected_individual })
        else
          grouped[statement.webpage.rdf_uri]
            .merge!(property_label => { cache: statement.cache, status: statement.status, selected_individual: statement.selected_individual })
            .merge!(archive_date: { cache: statement.webpage.archive_date })
        end
      end
    end

    def make_key(property_label, language)
      key = property_label.to_s.tr(" ", "_").downcase
      language.present? ? "#{key}_#{language.downcase}" : key
    rescue StandardError
      "failed_to_make_key"
    end

    def publishable?(data)
      publishable_states = %w[ok updated]
      return false unless publishable_states.include?(data.dig("dates", :status))
      return false unless publishable_states.include?(data.dig("location", :status)) || publishable_states.include?(data.dig("virtuallocation", :status))
      return false unless publishable_states.include?(data.dig("title_en", :status)) || publishable_states.include?(data.dig("title_fr", :status)) || publishable_states.include?(data.dig("title", :status))

      true
    end

    def parse_date(date_str)
      return patch_invalid_date unless date_str.present?

      date_array = date_str.to_s.start_with?("[") ? JSON.parse(date_str) : [date_str]
      date_array.map { |value| DateTime.parse(value) rescue nil }.compact.first || patch_invalid_date
    rescue StandardError
      patch_invalid_date
    end

    def patch_invalid_date
      DateTime.now + 1.year
    end

    def time_span
      start_date = parse_filter_date(filters[:startDate]) || Time.zone.now
      end_date = parse_filter_date(filters[:endDate]) || Time.zone.now + 5.years
      [start_date..end_date]
    end

    def parse_filter_date(value)
      Date.parse(value.to_s) if value.present?
    rescue StandardError
      nil
    end

    def filter_term(rows)
      return rows unless filters[:term].present?

      term = filters[:term].downcase
      rows.select { |row| [row[:title], row[:rdf_uri]].join(" ").downcase.include?(term) }
    end

    def sortable_value(value)
      value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime) ? value : value.to_s.downcase
    end

    def paginate_rows(rows)
      WillPaginate::Collection.create(page, per_page, rows.length) do |pager|
        pager.replace(rows[pager.offset, pager.per_page] || [])
      end
    end
  end
end
