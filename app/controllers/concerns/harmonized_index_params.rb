module HarmonizedIndexParams
  extend ActiveSupport::Concern

  include FilterableIndex
  include SortableIndex

  private

  def harmonized_index_params(
    source: params,
    allowed_filters:,
    allowed_sorts:,
    default_sort:,
    default_direction: "asc",
    default_page: 1,
    default_per_page:,
    max_per_page:
  )
    {
      filters: harmonized_index_filters(source: source, allowed: allowed_filters),
      sort: harmonized_index_sort(source: source, allowed: allowed_sorts, default: default_sort),
      direction: harmonized_index_direction(source: source, default: default_direction),
      page: harmonized_index_page(source: source, default: default_page),
      per_page: harmonized_index_per_page(source: source, default: default_per_page, max: max_per_page)
    }
  end

  def harmonized_index_filters(source: params, allowed:)
    extract_allowed_filters(source, Array(allowed))
  end

  def harmonized_index_sort(source: params, allowed:, default:)
    normalized_sort_param(source[:sort], allowed: allowed, default: default)
  end

  def harmonized_index_direction(source: params, default: "asc")
    normalized_direction_param(source[:direction], default: default)
  end

  def harmonized_index_page(source: params, default: 1)
    value = source[:page].to_i
    value.positive? ? value : default.to_i
  end

  def harmonized_index_per_page(source: params, default:, max:)
    value = source[:per_page].to_i
    value = default.to_i unless value.positive?
    [value, max.to_i].min
  end

  def harmonized_index_raw_params(source: params, allowed_filters:, preserve: [])
    source.to_unsafe_h
          .slice(*(Array(allowed_filters).map(&:to_s) + Array(preserve).map(&:to_s)))
          .compact_blank
  end

  def harmonized_index_canonical_params(index_params, default_sort:, default_direction:, default_per_page:, preserve: {}, exclude_filters: [])
    canonical_filters = index_params[:filters].to_h.symbolize_keys.except(*Array(exclude_filters))

    preserve.stringify_keys.merge(canonical_filters.stringify_keys).tap do |canonical|
      canonical["sort"] = index_params[:sort] if index_params[:sort] != default_sort
      canonical["direction"] = index_params[:direction] if index_params[:direction] != default_direction
      canonical["page"] = index_params[:page] if index_params[:page].to_i > 1
      canonical["per_page"] = index_params[:per_page] if index_params[:per_page].to_i != default_per_page
    end.compact_blank.transform_values(&:to_s)
  end
end
