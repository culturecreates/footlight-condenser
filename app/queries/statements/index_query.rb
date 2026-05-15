module Statements
  class IndexQuery
    FILTER_KEYS = %i[seedurl rdf_uri prop source cache status manual selected selected_individual].freeze
    DEFAULT_SORT = "id".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 100
    MAX_PER_PAGE = 200

    SORT_COLUMNS = {
      "id" => "statements.id",
      "cache" => "statements.cache",
      "status" => "statements.status",
      "manual" => "statements.manual",
      "selected_individual" => "statements.selected_individual",
      "cache_refreshed" => "statements.cache_refreshed",
      "cache_changed" => "statements.cache_changed",
      "updated_at" => "statements.updated_at"
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:, paginate: true)
      @filters = filters.to_h.symbolize_keys
      @sort = SORT_COLUMNS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
      @page = page
      @per_page = per_page
      @paginate = paginate
    end

    def call
      scope = Statement.includes(:webpage, source: [:property, :website])
      scope = filter_rdf_uri(scope)
      scope = filter_seedurl(scope)
      scope = scope.joins(source: :property).where(sources: { properties: { id: filters[:prop] } }) if filters[:prop].present?
      scope = scope.where(source_id: filters[:source]) if filters[:source].present?
      scope = scope.where("statements.cache LIKE ?", "%#{filters[:cache]}%") if filters[:cache].present?
      scope = scope.where(status: filters[:status]) if filters[:status].present?
      scope = filter_boolean(scope, :manual)
      scope = filter_source_selected(scope)
      scope = filter_boolean(scope, :selected_individual)
      scope = apply_sort(scope)
      paginate ? scope.paginate(page: page, per_page: per_page) : scope
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page, :paginate

    def filter_rdf_uri(scope)
      return scope unless filters[:rdf_uri].present?

      webpage_ids = Webpage.where(rdf_uri: filters[:rdf_uri]).select(:id)
      scope.where(webpage_id: webpage_ids)
    end

    def filter_seedurl(scope)
      return scope unless filters[:seedurl].present? && filters[:seedurl] != "all"

      scope.joins(webpage: :website).where(websites: { seedurl: filters[:seedurl] })
    end

    def filter_boolean(scope, key)
      return scope unless filters[key].present?

      scope.where(key => ActiveModel::Type::Boolean.new.cast(filters[key]))
    end

    def filter_source_selected(scope)
      return scope unless filters[:selected].present?

      scope.joins(:source).where(sources: { selected: ActiveModel::Type::Boolean.new.cast(filters[:selected]) })
    end

    def apply_sort(scope)
      if filters[:rdf_uri].present? && sort == DEFAULT_SORT
        scope.joins(:source).order(Arel.sql("sources.selected DESC, sources.property_id ASC, statements.id ASC"))
      else
        scope.order(Arel.sql("#{SORT_COLUMNS.fetch(sort)} #{direction.upcase}"))
      end
    end
  end
end
