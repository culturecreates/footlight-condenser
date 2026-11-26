module Distillator
  class WringerIssueSet
    SEVERITY_RANK = {
      "blocked" => 0,
      "failed" => 1,
      "warning" => 2,
      "info" => 3
    }.freeze
    BLOCKING_SEVERITIES = %w[blocked failed].freeze

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

    Result = Struct.new(:matches, :primary, :blocking, keyword_init: true)

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
      blockers = matches.select { |match| blocking_rule?(match[:rule]) }
      Result.new(matches: matches, primary: select_primary(matches), blocking: select_primary(blockers))
    end

    def self.blocking_rule?(rule)
      return false unless rule

      severity = rule["severity"] || rule[:severity]
      policy = rule["policy"] || rule[:policy] || {}
      BLOCKING_SEVERITIES.include?(severity.to_s) || (policy["action"] || policy[:action]).to_s == "abort_update"
    end

    # Older records copied the primary issue to the blocking key even for observations.
    # Keep unknown explicit blockers and any independent evidence of a blocked fetch.
    def self.reported_blocking_key(signals)
      data = signals.to_h.stringify_keys
      explicit = data["blocking_issue_key"].presence
      if explicit
        rule = Distillator::WringerRules.find(explicit)&.last
        return explicit if rule.nil? || blocking_rule?(rule)
      end

      primary = data["primary_issue_key"].presence
      return primary if primary && BLOCKING_SEVERITIES.include?(data["primary_issue_severity"].to_s)

      # A historical primary label alone may describe an observation. The
      # issue list records the rules that actually matched the fetch.
      Array(data["issue_keys"]).find do |key|
        blocking_rule?(Distillator::WringerRules.find(key)&.last)
      end
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
