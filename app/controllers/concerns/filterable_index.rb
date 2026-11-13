module FilterableIndex
  extend ActiveSupport::Concern

  private

  def extract_allowed_filters(source, keys)
    keys.each_with_object({}) do |key, acc|
      cleaned = clean_filter_value(source[key])
      acc[key] = cleaned if cleaned
    end
  end

  def clean_filter_value(value)
    return nil if value.nil?

    cleaned = value.to_s.strip
    cleaned.presence
  end
end
