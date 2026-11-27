module HarmonizedTableHelper
  def harmonized_sortable_header(column, label = nil, filters: nil, current_sort: nil, current_direction: nil)
    label ||= column.to_s.titleize
    active_sort = current_sort || params[:sort]
    active_direction = current_direction || params[:direction]

    display_label = label.dup
    active = active_sort.to_s == column.to_s
    display_label += active_direction.to_s == "asc" ? " ↑" : " ↓" if active

    next_direction =
      if active && active_direction.to_s == "asc"
        "desc"
      else
        "asc"
      end

    route_params =
      if respond_to?(:request) && request.present?
        request.path_parameters.except(:format).symbolize_keys
      else
        {}
      end

    filter_params = (filters || @filters || {}).to_h.symbolize_keys.except(:page).compact_blank
    link_params = route_params.merge(filter_params).merge(sort: column, direction: next_direction)
    html_options = active ? { class: "is-active-sort", "aria-current": "true" } : {}

    link_to(display_label.html_safe, link_params, html_options)
  end
end
