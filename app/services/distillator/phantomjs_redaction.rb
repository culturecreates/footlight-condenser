module Distillator
  class PhantomjsRedaction
    KEY_PATH = %r{((?:https?://phantomjscloud\.com\.?(?::\d+)?|(?<![\w./-]))/api/browser/v2/)([^/?#\s"'<>\\]+)}i
    MASK = "[FILTERED]".freeze

    def initialize(request_url)
      key = request_url.to_s[KEY_PATH, 2]
      @pattern = key && key != MASK ? Regexp.union(KEY_PATH, key) : KEY_PATH
    end

    def call(value)
      case value
      when String
        value.gsub(@pattern) { "#{Regexp.last_match(1)}#{MASK}" }
      when Hash
        value.transform_values { |item| call(item) }
      when Array
        value.map { |item| call(item) }
      else
        value
      end
    end

    def fetch_result(result)
      # Page content still needs to reach the extraction pipeline verbatim.
      metadata = call(result.except(:body, :raw_body))
      metadata[:body] = result[:body].is_a?(String) ? result[:body] : call(result[:body])
      metadata[:raw_body] = result[:raw_body]
      metadata
    end
  end
end
