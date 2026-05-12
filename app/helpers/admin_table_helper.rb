module AdminTableHelper
  def admin_sortable(column, label = nil, filters: nil, current_sort: nil, current_direction: nil)
    label ||= column.to_s.titleize
    display_label = label.dup
    active_sort = current_sort || params[:sort]
    active_direction = current_direction || params[:direction]

    if active_sort.to_s == column.to_s
      display_label += active_direction.to_s == "asc" ? " ↑" : " ↓"
    end

    next_direction =
      if active_sort.to_s == column.to_s && active_direction.to_s == "asc"
        "desc"
      else
        "asc"
      end

    route_params =
      if respond_to?(:request) && request.present?
        request.path_parameters.slice(:controller, :action).symbolize_keys
      else
        {}
      end

    link_params = route_params.merge((filters || @filters || {}).merge(sort: column, direction: next_direction))
    link_to(display_label.html_safe, link_params)
  end
end
