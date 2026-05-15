require "will_paginate/collection"

module Resources
  class IndexQuery
    FILTER_KEYS = %i[seedurl term].freeze
    DEFAULT_SORT = "rdf_uri".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = %w[rdf_uri rdfs_class_name name archive_date].freeze

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
      rows = webpage_scope.map do |webpage|
        {
          rdf_uri: webpage.rdf_uri,
          rdfs_class_name: webpage.rdfs_class&.name.to_s,
          name: resource_name_for(webpage.rdf_uri),
          archive_date: webpage.archive_date
        }
      end
      rows = filter_term(rows)
      rows = rows.sort_by { |row| sortable_value(row[sort]) }
      rows.reverse! if direction == "desc"
      paginate_rows(rows)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def webpage_scope
      scope = Webpage.joins(:website, :rdfs_class).includes(:rdfs_class).where(websites: { seedurl: filters[:seedurl] })
      scope.select("DISTINCT ON (webpages.rdf_uri) webpages.*").order("webpages.rdf_uri ASC, webpages.archive_date DESC")
    end

    def resource_name_for(rdf_uri)
      name_property_ids = Property.where(label: "Name").select(:id)
      Statement.joins(:source)
               .where(webpage_id: Webpage.where(rdf_uri: rdf_uri).select(:id), sources: { property_id: name_property_ids })
               .pick(:cache)
    end

    def filter_term(rows)
      return rows unless filters[:term].present?

      term = filters[:term].downcase
      rows.select do |row|
        [row[:rdf_uri], row[:rdfs_class_name], row[:name]].compact.join(" ").downcase.include?(term)
      end
    end

    def sortable_value(value)
      value.to_s.downcase
    end

    def paginate_rows(rows)
      WillPaginate::Collection.create(page, per_page, rows.length) do |pager|
        pager.replace(rows[pager.offset, pager.per_page] || [])
      end
    end
  end
end
