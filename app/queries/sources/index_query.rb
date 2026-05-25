module Sources
  class IndexQuery
    FILTER_KEYS = %i[term algorithm_value selected auto_review render_js language website_id property_id].freeze
    DEFAULT_SORT = "property_id".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = {
      "id" => :id,
      "property_id" => :property_id,
      "label" => :label,
      "algorithm_value" => :algorithm_value,
      "selected" => :selected,
      "render_js" => :render_js,
      "auto_review" => :auto_review,
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
      scope = Source.all
      scope = filter_term(scope)
      scope = filter_boolean(scope, :selected)
      scope = filter_boolean(scope, :auto_review)
      scope = filter_boolean(scope, :render_js)
      scope = scope.where(language: filters[:language]) if filters[:language].present?
      scope = scope.where(website_id: filters[:website_id]) if filters[:website_id].present?
      scope = scope.where(property_id: filters[:property_id]) if filters[:property_id].present?
      apply_sort(scope).paginate(page: page, per_page: per_page)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def filter_term(scope)
      term = filters[:term].presence || filters[:algorithm_value].presence
      return scope unless term.present?

      scope.where("LOWER(algorithm_value) LIKE ?", "%#{term.downcase}%")
    end

    def filter_boolean(scope, key)
      case filters[key].to_s
      when "true"
        scope.where(key => true)
      when "false"
        scope.where(key => false)
      else
        scope
      end
    end

    def apply_sort(scope)
      if sort == DEFAULT_SORT && direction == DEFAULT_DIRECTION
        scope.order(property_id: :asc, language: :asc, selected: :desc, id: :asc)
      else
        scope.order(SORT_COLUMNS.fetch(sort) => direction.to_sym, id: :asc)
      end
    end
  end
end
