module Distillator
  class JsonPostFetcher
    def self.call(agent:, url:, scrape_options:)
      agent.post(url, request_body(scrape_options), request_headers(scrape_options))
    end

    def self.request_headers(scrape_options)
      headers = scrape_options[:headers] || scrape_options["headers"] || {}
      normalized = headers.to_h.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
      return normalized if normalized.keys.any? { |key| key.downcase == "content-type" }

      normalized.merge("Content-Type" => "application/json")
    end

    def self.request_body(scrape_options)
      scrape_options[:request_body] || scrape_options["request_body"] || ""
    end
  end
end
