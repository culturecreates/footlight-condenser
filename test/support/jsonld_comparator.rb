require "json"

module JsonldComparator
  VOLATILE_KEYS = %w[
    created_at
    updated_at
    generated_at
    debug
    debug_info
    trace
  ].freeze

  # Arrays are canonicalized only at explicitly declared unordered paths.
  # Root JSON-LD export is a set of events and can be compared order-independently.
  UNORDERED_ARRAY_PATHS = [
    []
  ].freeze

  def canonical_jsonld(json)
    value = parse_jsonld_if_string(json)
    canonicalize_jsonld(value, [])
  end

  def assert_jsonld_equal(expected, actual)
    expected_canonical = canonical_jsonld(expected)
    actual_canonical = canonical_jsonld(actual)

    diff = first_jsonld_difference(expected_canonical, actual_canonical, [])
    return unless diff

    flunk <<~MSG
      JSON-LD mismatch at #{format_jsonld_path(diff[:path])}
      Reason: #{diff[:reason]}
      Expected: #{diff[:expected].inspect}
      Actual: #{diff[:actual].inspect}
    MSG
  end

  private

  def parse_jsonld_if_string(value)
    return value unless value.is_a?(String)

    JSON.parse(value)
  rescue JSON::ParserError
    value
  end

  def canonicalize_jsonld(value, path)
    case value
    when Hash
      canonical_pairs = value.each_with_object([]) do |(key, child), out|
        next if volatile_key?(key)

        out << [key, canonicalize_jsonld(child, path + [key])]
      end

      canonical_pairs
        .sort_by { |(key, _)| [key.class.name, key.to_s] }
        .each_with_object({}) { |(key, child), out| out[key] = child }
    when Array
      canonical_items = value.each_with_index.map do |child, index|
        canonicalize_jsonld(child, path + [index])
      end

      return canonical_items unless unordered_array_path?(path)

      ensure_sortable_unordered_array!(canonical_items, path)
      canonical_items.sort_by { |child| canonical_sort_key(child) }
    else
      value
    end
  end

  def volatile_key?(key)
    VOLATILE_KEYS.include?(key.to_s)
  end

  def unordered_array_path?(path)
    UNORDERED_ARRAY_PATHS.include?(path)
  end

  def ensure_sortable_unordered_array!(items, path)
    return if items.empty?

    unless items.all? { |item| item.is_a?(Hash) }
      raise ArgumentError, "Cannot canonicalize unordered array at #{format_jsonld_path(path)} with non-hash elements"
    end

    items.each do |item|
      canonical_sort_key(item)
    rescue JSON::GeneratorError => e
      raise ArgumentError, "Cannot canonicalize unordered array at #{format_jsonld_path(path)}: #{e.message}"
    end
  end

  def canonical_sort_key(value)
    JSON.generate(canonical_jsonld(value))
  end

  def first_jsonld_difference(expected, actual, path)
    if expected.class != actual.class
      return {
        path: path,
        reason: "type mismatch (#{expected.class} != #{actual.class})",
        expected: expected,
        actual: actual
      }
    end

    case expected
    when Hash
      missing_key = (expected.keys - actual.keys).sort_by { |key| [key.class.name, key.to_s] }.first
      if missing_key
        return {
          path: path + [missing_key],
          reason: "missing key",
          expected: expected[missing_key],
          actual: :__missing__
        }
      end

      extra_key = (actual.keys - expected.keys).sort_by { |key| [key.class.name, key.to_s] }.first
      if extra_key
        return {
          path: path + [extra_key],
          reason: "unexpected key",
          expected: :__missing__,
          actual: actual[extra_key]
        }
      end

      expected.keys.sort_by { |key| [key.class.name, key.to_s] }.each do |key|
        diff = first_jsonld_difference(expected[key], actual[key], path + [key])
        return diff if diff
      end
    when Array
      if expected.length != actual.length
        return {
          path: path,
          reason: "array length mismatch",
          expected: expected.length,
          actual: actual.length
        }
      end

      expected.each_index do |index|
        diff = first_jsonld_difference(expected[index], actual[index], path + [index])
        return diff if diff
      end
    else
      return if expected == actual

      return {
        path: path,
        reason: "value mismatch",
        expected: expected,
        actual: actual
      }
    end

    nil
  end

  def format_jsonld_path(path)
    return "root" if path.empty?

    path.each_with_index.map do |segment, index|
      if segment.is_a?(Integer)
        "[#{segment}]"
      elsif index.zero?
        segment.to_s
      else
        ".#{segment}"
      end
    end.join
  end
end
