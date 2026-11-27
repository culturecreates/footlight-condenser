require "will_paginate/collection"

module Reports
  class IndexQuery
    FILTER_KEYS = %i[source_id startDate endDate term].freeze
    DEFAULT_SORT = "event_title".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = %w[event_title cache archive_date webpage_id rdf_uri].freeze

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
      rows = statements.map do |statement|
        {
          event_title: filtered_event_titles[statement.webpage_id].to_s,
          cache: statement.cache.to_s,
          webpage_id: statement.webpage_id,
          archive_date: filtered_archive_dates[statement.webpage_id],
          rdf_uri: filtered_event_uris[statement.webpage_id].to_s
        }
      end
      rows = filter_term(rows)
      rows = rows.sort_by { |row| sortable_value(row[sort]) }
      rows.reverse! if direction == "desc"
      paginate_rows(rows)
    end

    def source
      @source ||= Source.find_by(id: filters[:source_id])
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def statements
      return Statement.none if source.blank?

      @statements ||= Statement
                      .joins({ source: [:property, :website] }, :webpage)
                      .where(source_id: source.id)
                      .where(webpages: { archive_date: time_span })
                      .order(:cache)
    end

    def time_span
      start_date = parse_date(filters[:startDate]) || Time.zone.now
      end_date = parse_date(filters[:endDate]) || Time.zone.now.next_year + 6.months
      [start_date..end_date]
    end

    def parse_date(value)
      Date.parse(value.to_s) if value.present?
    rescue StandardError
      nil
    end

    def filtered_event_titles
      @filtered_event_titles ||= begin
        return {} if source.blank?

        title_property = Property.where(label: "Title")
        title_source = Source.joins(:property).where(property: title_property, website: source.website, selected: true)
        event_titles = Statement.joins({ source: [:property, :website] }, :webpage)
                                .where(source_id: title_source.select(:id))
                                .where(webpages: { archive_date: [Time.zone.now - 10.years..Time.zone.now + 10.years] })
                                .order(:cache)
        statements.each_with_object({}) do |statement, acc|
          title = event_titles.find { |event_title| event_title.webpage_id == statement.webpage_id }
          acc[statement.webpage_id] = title.cache if title
        end
      end
    end

    def filtered_archive_dates
      @filtered_archive_dates ||= begin
        return {} if source.blank?

        webpages = Webpage.joins(:website).where(rdfs_class: 1, websites: { seedurl: source.website.seedurl })
        statements.each_with_object({}) do |statement, acc|
          webpage = webpages.find { |row| row.id == statement.webpage_id }
          acc[statement.webpage_id] = webpage.archive_date if webpage
        end
      end
    end

    def filtered_event_uris
      @filtered_event_uris ||= begin
        return {} if source.blank?

        webpages = Webpage.joins(:website).where(rdfs_class: 1, websites: { seedurl: source.website.seedurl })
        statements.each_with_object({}) do |statement, acc|
          webpage = webpages.find { |row| row.id == statement.webpage_id }
          acc[statement.webpage_id] = webpage.rdf_uri if webpage
        end
      end
    end

    def filter_term(rows)
      return rows unless filters[:term].present?

      term = filters[:term].downcase
      rows.select { |row| row.values.compact.join(" ").downcase.include?(term) }
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
