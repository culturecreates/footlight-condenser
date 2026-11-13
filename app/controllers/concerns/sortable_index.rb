module SortableIndex
  extend ActiveSupport::Concern

  private

  def normalized_sort_param(value, allowed:, default:)
    value.to_s.presence_in(Array(allowed).map(&:to_s)) || default.to_s
  end

  def normalized_direction_param(value, default: "asc")
    value.to_s.presence_in(%w[asc desc]) || default.to_s
  end
end
