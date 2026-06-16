module Distillator
  class WringerIssueSet
    SEVERITY_RANK = {
      "blocked" => 0,
      "failed" => 1,
      "warning" => 2,
      "info" => 3
    }.freeze

    CATEGORY_RANK = {
      "anti_bot" => 0,
      "security" => 1,
      "network" => 2,
      "redirect" => 3,
      "http" => 4,
      "content" => 5,
      "fetch_mode" => 6,
      "renderer" => 7
    }.freeze

    Result = Struct.new(:matches, :primary, keyword_init: true)

    def self.call(body:, http_code:, final_url:, hints: [], signals: {}, rules: nil, logger: Rails.logger)
      matches = Distillator::WringerSystemErrorMatcher.all_matches(
        body: body,
        http_code: http_code,
        final_url: final_url,
        hints: hints,
        signals: signals,
        rules: rules,
        logger: logger
      )
      Result.new(matches: matches, primary: select_primary(matches))
    end

    def self.select_primary(matches)
      indexed = Array(matches).each_with_index.to_a

      indexed.min_by do |(match, index)|
        rule = match[:rule] || {}
        category = rule["category"] || rule[:category]
        severity = rule["severity"] || rule[:severity]

        [
          CATEGORY_RANK.fetch(category.to_s, 99),
          SEVERITY_RANK.fetch(severity.to_s, 99),
          index
        ]
      end&.first
    end
  end
end
