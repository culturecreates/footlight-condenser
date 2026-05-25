module Webpages
  class IndexQuery
    FILTER_KEYS = %i[
      term
      website_id
      language
      rdfs_class_id
      rdfs_class
      archive_state
      url_kind
      publishable
      scope
    ].freeze

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

    def self.scope(filters:)
      new(
        filters: filters,
        sort: DEFAULT_SORT,
        direction: DEFAULT_DIRECTION,
        page: nil,
        per_page: nil,
        paginate: false
      ).scope
    end

    def initialize(filters:, sort:, direction:, page: nil, per_page: nil, paginate: true)
      @filters = filters.to_h.symbolize_keys
      @sort = SORT_COLUMNS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
      @page = page
      @per_page = per_page
      @paginate = paginate
    end

    def call
      scope = base_scope
      scope = apply_filters(scope)
      scope = scope.order(SORT_COLUMNS.fetch(sort) => direction.to_sym)

      paginate ? scope.paginate(page: page, per_page: per_page) : scope
    end

    def scope
      apply_filters(base_scope)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page, :paginate

    def base_scope
      return Webpage.all if filters[:scope].to_s == "all"

      Webpage.active.publishable
    end

    def apply_filters(scope)
      scope = filter_term(scope)
      scope = scope.where(website_id: filters[:website_id]) if filters[:website_id].present?
      scope = scope.where(language: filters[:language]) if filters[:language].present?
      scope = filter_rdfs_class(scope)
      scope = filter_url_kind(scope)
      scope = filter_publishable(scope)
      filter_archive_state(scope)
      
    end

    def filter_term(scope)
      return scope unless filters[:term].present?

      pattern = "%#{filters[:term].downcase}%"
      scope.where("LOWER(url) LIKE :pattern OR LOWER(rdf_uri) LIKE :pattern", pattern: pattern)
    end

    def filter_rdfs_class(scope)
      return scope.where(rdfs_class_id: filters[:rdfs_class_id]) if filters[:rdfs_class_id].present?
      return scope unless filters[:rdfs_class].present?

      case filters[:rdfs_class].to_s
      when "Other"
        scope.left_outer_joins(:rdfs_class)
             .where("rdfs_classes.id IS NULL OR rdfs_classes.name NOT IN (?)", Distillator::WebsiteWebpageSummary::CLASS_BUCKETS)
      else
        scope.joins(:rdfs_class).where(rdfs_classes: { name: filters[:rdfs_class].to_s })
      end
    end

    def filter_url_kind(scope)
      case filters[:url_kind].to_s
      when "public"
        scope.public_source_urls
      when "internal"
        scope.internal_uris
      else
        scope
      end
    end

    def filter_publishable(scope)
      case filters[:publishable].to_s
      when "true"
        scope.publishable
      when "false"
        return scope unless filters[:scope].to_s == "all"

        scope.not_publishable
      else
        scope
      end
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
