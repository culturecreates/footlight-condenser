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
        match_details = matched_details(match)
        next unless match_details

        logger.warn "[Wringer] #{name} matched (code=#{http_code}, url=#{final_url})"

        {
          key: name.to_s,
          error: "#{name} detected",
          error_type: value(policy, :error_code) || name.to_s,
          policy: policy,
          rule: rule,
          match_details: match_details,
          action: value(policy, :action),
          retry: value(policy, :retry),
          cache: value(policy, :cache),
          delete: value(policy, :delete)
        }
      end
    end

    private

    attr_reader :body, :body_value, :http_code, :final_url, :hints, :signals, :rules, :logger

    def matched_details(match)
      details = nil
      http_code_match = value(match, :http_code)
      if http_code_match
        codes = Array(http_code_match).map(&:to_i)
        return nil unless codes.include?(http_code)

        details ||= {
          source: "http_code",
          pattern: codes.join(", "),
          snippet: "HTTP #{http_code}"
        }
      end

      body_contains = value(match, :body_contains)
      if body_contains
        matched_text = Array(body_contains).find { |text| body.include?(text) }
        return nil unless matched_text

        details ||= {
          source: "html",
          pattern: matched_text,
          snippet: matched_snippet(body, matched_text)
        }
      end

      body_text_contains = value(match, :body_text_contains)
      if body_text_contains
        matched_text = Array(body_text_contains).find { |text| body_text.include?(text) }
        return nil unless matched_text

        details ||= {
          source: "body_text",
          pattern: matched_text,
          snippet: matched_snippet(body_text, matched_text)
        }
      end

      body_blank = value(match, :body_blank)
      if body_blank
        return nil unless body_value.nil? || (body_value.respond_to?(:strip) && body_value.strip.empty?)

        details ||= {
          source: "body",
          pattern: "body_blank",
          snippet: "Body was blank"
        }
      end

      hint_match = value(match, :hints)
      if hint_match
        matched_hint = Array(hint_match).find { |hint| hints.include?(hint.to_s) }
        return nil unless matched_hint

        details ||= {
          source: "hint",
          pattern: matched_hint.to_s,
          snippet: matched_hint.to_s
        }
      end

      network_status_match = value(match, :network_status)
      if network_status_match.present?
        return nil unless signals["network_status"].to_s == network_status_match.to_s

        details ||= {
          source: "signal",
          pattern: "network_status=#{network_status_match}",
          snippet: "network_status=#{signals['network_status']}"
        }
      end

      content_type_match = value(match, :content_type)
      if content_type_match.present?
        return nil unless signals["content_type"].to_s == content_type_match.to_s

        details ||= {
          source: "signal",
          pattern: "content_type=#{content_type_match}",
          snippet: "content_type=#{signals['content_type']}"
        }
      end

      signal_match = value(match, :signals)
      if signal_match
        matched_pair = signal_match.to_h.find do |key, expected|
          signals[key.to_s].to_s == expected.to_s
        end
        return nil unless signal_match.to_h.all? { |key, expected| signals[key.to_s].to_s == expected.to_s }

        details ||= {
          source: "signal",
          pattern: "#{matched_pair.first}=#{matched_pair.last}",
          snippet: "#{matched_pair.first}=#{signals[matched_pair.first.to_s]}"
        }
      end

      final_url_patterns = value(match, :final_url_patterns)
      if final_url_patterns
        matched_pattern = Array(final_url_patterns).find do |pattern|
          Regexp.new(pattern).match?(final_url)
        rescue RegexpError
          false
        end
        return nil unless matched_pattern

        details ||= {
          source: "final_url",
          pattern: matched_pattern,
          snippet: matched_snippet(final_url, matched_pattern)
        }
      end

      details || { source: "rule", pattern: "matched", snippet: "Rule matched" }
    end

    def value(hash, key)
      return nil unless hash.respond_to?(:[])

      return hash[key.to_s] if hash.respond_to?(:key?) && hash.key?(key.to_s)
      return hash[key.to_sym] if hash.respond_to?(:key?) && hash.key?(key.to_sym)

      hash[key.to_s] || hash[key.to_sym]
    end

    def body_text
      @body_text ||= Nokogiri::HTML(body.to_s).text.to_s.squish
    rescue StandardError
      body.to_s
    end

    def matched_snippet(text, pattern, max_length: 140)
      raw_text = text.to_s.squish
      return raw_text.first(max_length) if pattern.blank?

      index = raw_text.index(pattern.to_s)
      return raw_text.first(max_length) unless index

      start = [index - 40, 0].max
      snippet = raw_text[start, max_length]
      snippet.to_s
    end
  end
end
