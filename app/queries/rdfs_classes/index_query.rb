module RdfsClasses
  class IndexQuery
    FILTER_KEYS = %i[term].freeze
    DEFAULT_SORT = "name".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = {
      "id" => :id,
      "name" => :name,
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
      scope = RdfsClass.all
      scope = filter_term(scope)
      scope.order(SORT_COLUMNS.fetch(sort) => direction.to_sym).paginate(page: page, per_page: per_page)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def filter_term(scope)
      return scope unless filters[:term].present?

      scope.where("LOWER(name) LIKE ?", "%#{filters[:term].downcase}%")
    end
  end
end
