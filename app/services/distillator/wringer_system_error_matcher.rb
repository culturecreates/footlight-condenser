module Distillator
  class WringerSystemErrorMatcher
    def self.call(body:, http_code:, final_url:, hints: [], signals: {}, rules: nil, logger: Rails.logger)
      matches = all_matches(
        body: body,
        http_code: http_code,
        final_url: final_url,
        hints: hints,
        signals: signals,
        rules: rules,
        logger: logger
      )

      Distillator::WringerIssueSet.select_primary(matches)
    end

    def self.all_matches(body:, http_code:, final_url:, hints: [], signals: {}, rules: nil, logger: Rails.logger)
      new(
        body: body,
        http_code: http_code,
        final_url: final_url,
        hints: hints,
        signals: signals,
        rules: rules || Distillator::WringerRules.all,
        logger: logger
      ).all_matches
    end

    def initialize(body:, http_code:, final_url:, hints:, signals:, rules:, logger:)
      @body_value = body
      @body = body.to_s
      @http_code = http_code.to_i
      @final_url = final_url.to_s
      @hints = Array(hints).map(&:to_s)
      @signals = (signals || {}).to_h.stringify_keys
      @rules = Array(rules)
      @logger = logger || Rails.logger
    end

    def call
      all_matches.first
    end

    def all_matches
      rules.filter_map do |name, rule|
        match = value(rule, :match) || {}
        policy = value(rule, :policy) || {}
        next unless matched?(match)

        logger.warn "[Wringer] #{name} matched (code=#{http_code}, url=#{final_url})"

        {
          key: name.to_s,
          error: "#{name} detected",
          error_type: value(policy, :error_code) || name.to_s,
          policy: policy,
          rule: rule,
          action: value(policy, :action),
          retry: value(policy, :retry),
          cache: value(policy, :cache),
          delete: value(policy, :delete)
        }
      end
    end

    private

    attr_reader :body, :body_value, :http_code, :final_url, :hints, :signals, :rules, :logger

    def matched?(match)
      matched = true

      http_code_match = value(match, :http_code)
      if http_code_match
        codes = Array(http_code_match).map(&:to_i)
        matched &&= codes.include?(http_code)
      end

      body_contains = value(match, :body_contains)
      if body_contains
        matched &&= Array(body_contains).any? { |text| body.include?(text) }
      end

      body_blank = value(match, :body_blank)
      matched &&= body_value.nil? || (body_value.respond_to?(:strip) && body_value.strip.empty?) if body_blank

      hint_match = value(match, :hints)
      if hint_match
        matched &&= Array(hint_match).any? { |hint| hints.include?(hint.to_s) }
      end

      network_status_match = value(match, :network_status)
      matched &&= signals["network_status"].to_s == network_status_match.to_s if network_status_match.present?

      content_type_match = value(match, :content_type)
      matched &&= signals["content_type"].to_s == content_type_match.to_s if content_type_match.present?

      signal_match = value(match, :signals)
      if signal_match
        matched &&= signal_match.to_h.all? do |key, expected|
          signals[key.to_s].to_s == expected.to_s
        end
      end

      final_url_patterns = value(match, :final_url_patterns)
      if final_url_patterns
        matched &&= Array(final_url_patterns).any? do |pattern|
          Regexp.new(pattern).match?(final_url)
        rescue RegexpError
          false
        end
      end

      matched
    end

    def value(hash, key)
      return nil unless hash.respond_to?(:[])

      return hash[key.to_s] if hash.respond_to?(:key?) && hash.key?(key.to_s)
      return hash[key.to_sym] if hash.respond_to?(:key?) && hash.key?(key.to_sym)

      hash[key.to_s] || hash[key.to_sym]
    end
  end
end
