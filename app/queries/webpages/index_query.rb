module Webpages
  class IndexQuery
    FILTER_KEYS = %i[term website_id language rdfs_class_id archive_state].freeze
    DEFAULT_SORT = "url".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = {
      "url" => :url,
      "website_id" => :website_id,
      "language" => :language,
      "updated_at" => :updated_at
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:)
      @filters = filters.to_h.symbolize_keys
      @sort = SORT_COLUMNS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
      @page = page
      @per_page = per_page
    end

    def call
      scope = Webpage.all
      scope = filter_term(scope)
      scope = scope.where(website_id: filters[:website_id]) if filters[:website_id].present?
      scope = scope.where(language: filters[:language]) if filters[:language].present?
      scope = scope.where(rdfs_class_id: filters[:rdfs_class_id]) if filters[:rdfs_class_id].present?
      scope = filter_archive_state(scope)
      scope.order(SORT_COLUMNS.fetch(sort) => direction.to_sym).paginate(page: page, per_page: per_page)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def filter_term(scope)
      return scope unless filters[:term].present?

      pattern = "%#{filters[:term].downcase}%"
      scope.where("LOWER(url) LIKE :pattern OR LOWER(rdf_uri) LIKE :pattern", pattern: pattern)
    end

    def filter_archive_state(scope)
      case filters[:archive_state].to_s
      when "archived"
        scope.where("archive_date <= ?", Time.zone.now)
      when "active"
        scope.where("archive_date IS NULL OR archive_date > ?", Time.zone.now)
      else
        scope
      end
    end
  end
end
