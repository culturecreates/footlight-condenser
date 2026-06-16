# frozen_string_literal: true

module Distillator
  # Materializes derived health and issue fields onto a FetchCache row.
  #
  # This keeps cache index/summary pages fast and explicit. Expensive or
  # body-dependent classification happens when the cache row is saved, not when
  # large cache tables are listed.
  #
  # Call chain:
  #
  #   FetchCacheStore#write_fetch_result
  #     -> Distillator::FetchCache#before_save
  #     -> Distillator::CacheHealthMaterializer.call(cache)
  #     -> Distillator::CacheHealth.call(cache)
  #     -> Distillator::WringerIssueSet.call(...)
  #     -> attributes assigned onto FetchCache
  #
  # Issue state originates earlier in the fetch pipeline:
  #
  #   FetchService
  #     -> WringerIssueSet / WringerSystemErrorMatcher
  #     -> config/wringer.yml
  #     -> fetch_result[:wringer][:signals]
  #     -> FetchCacheStore
  #     -> FetchCache signals/hints
  #     -> CacheHealthMaterializer
  #
  # Materialized fields include health status, byte counts, redirect state,
  # network/content status, hint keys, primary issue fields, issue keys/hints,
  # and delete_candidate.
  #
  # Important last-good rule:
  #
  #   When a failed refresh preserves last-good content, cache.body may contain
  #   old successful content while signals/hints describe the latest failure.
  #   In that case, issue matching must prefer latest attempt metadata and avoid
  #   deriving the primary issue from stale body text.
  #
  # This class mutates only the passed cache object. It does not save by itself.
  class CacheHealthMaterializer
    # Assign materialized attributes to the cache object.
    #
    # @param cache [Distillator::FetchCache]
    # @return [Distillator::FetchCache]
    def self.call(cache)
      new(cache).call
    end

    # Compute materialized attributes without mutating the cache object.
    #
    # @param cache [Distillator::FetchCache]
    # @return [Hash]
    def self.attributes_for(cache)
      new(cache).attributes
    end

    # @param cache [Distillator::FetchCache]
    def initialize(cache)
      @cache = cache
    end

    # Assign attributes to the cache object and return it.
    #
    # @return [Distillator::FetchCache]
    def call
      cache.assign_attributes(attributes)
      cache
    end

    # Build all materialized health and issue attributes.
    #
    # @return [Hash]
    def attributes
      health = Distillator::CacheHealth.call(cache)
      issue_set = Distillator::WringerIssueSet.call(
        body: body_for_issue_matching,
        http_code: cache.http_response_code,
        final_url: cache.final_url,
        hints: hints,
        signals: signals
      )

      primary_issue = primary_issue_for(issue_set)
      primary_issue_key = primary_issue&.[](:key) || signal("primary_issue_key")
      primary_issue_rule = primary_issue&.[](:rule) || Distillator::WringerRules.find(primary_issue_key)&.last || {}
      primary_issue_hints = Array(primary_issue_rule["hints"] || primary_issue_rule[:hints]).map(&:to_s)
      primary_issue_policy = primary_issue&.[](:policy) || primary_issue_rule["policy"] || primary_issue_rule[:policy] || {}

      issue_keys = (
        issue_set.matches.map { |match| match[:key].to_s } +
        Array(signal("issue_keys")).map(&:to_s) +
        Array(primary_issue_key).compact.map(&:to_s)
      ).uniq

      {
        health_status: health.status.to_s,
        health_severity: health.severity,
        health_reasons: health.reasons,
        html_bytes: cache.html.to_s.bytesize,
        body_bytes: cache.body.to_s.bytesize,
        redirected: redirected?,
        network_status: signal("network_status"),
        content_type: signal("content_type"),
        hint_keys: hints,
        primary_issue_key: primary_issue_key,
        primary_issue_error_code: primary_issue&.[](:error_type) || signal("primary_issue_error_code"),
        primary_issue_label: primary_issue&.dig(:rule, "label") ||
          primary_issue&.dig(:rule, :label) ||
          signal("primary_issue_label") ||
          primary_issue_rule["label"] ||
          primary_issue_rule[:label],
        primary_issue_severity: primary_issue&.dig(:rule, "severity") ||
          primary_issue&.dig(:rule, :severity) ||
          signal("primary_issue_severity") ||
          primary_issue_rule["severity"] ||
          primary_issue_rule[:severity],
        primary_issue_category: primary_issue&.dig(:rule, "category") ||
          primary_issue&.dig(:rule, :category) ||
          signal("primary_issue_category") ||
          primary_issue_rule["category"] ||
          primary_issue_rule[:category],
        issue_keys: issue_keys,
        issue_hints: (hints + primary_issue_hints).uniq,
        delete_candidate: delete_candidate?(primary_issue, primary_issue_policy)
      }
    end

    private

    attr_reader :cache

    # Cache signals as a plain hash.
    #
    # @return [Hash]
    def signals
      @signals ||= (cache.signals || {}).to_h
    end

    # Read a signal using string or symbol keys.
    #
    # @param key [String, Symbol]
    # @return [Object, nil]
    def signal(key)
      signals[key.to_s] || signals[key.to_sym]
    end

    # Cache hints as unique strings.
    #
    # @return [Array<String>]
    def hints
      @hints ||= Array(cache.hints).map(&:to_s).uniq
    end

    # Body used for issue matching.
    #
    # If the latest refresh failed but last-good content was preserved, cache.body
    # is stale success content. Matching against it can produce misleading issue
    # badges, so use nil and let hints/signals/http_code drive classification.
    #
    # @return [String, nil]
    def body_for_issue_matching
      last_good_preserved_failure? ? nil : cache.body
    end

    # Whether this row is currently serving preserved last-good content after a
    # failed or unusable refresh attempt.
    #
    # @return [Boolean]
    def last_good_preserved_failure?
      truthy_signal?("last_good_preserved_failure") || hints.include?("last_good_preserved_failure")
    end

    # Determine whether the row should be marked as a delete candidate.
    #
    # Delete candidacy may come directly from the primary issue match, from
    # signals, or from the YAML policy. The actual deletion decision still lives
    # in WebpageRemovalCandidate, which re-checks current YAML policy.
    #
    # @param primary_issue [Hash, nil]
    # @param primary_issue_policy [Hash]
    # @return [Boolean]
    def delete_candidate?(primary_issue, primary_issue_policy)
      primary_issue&.[](:delete) == true ||
        truthy_signal?("primary_issue_delete") ||
        policy_value(primary_issue_policy, :delete) == true
    end

    # Interpret common serialized boolean encodings.
    #
    # @param key [String, Symbol]
    # @return [Boolean]
    def truthy_signal?(key)
      value = signal(key)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    # Safely read string-keyed or symbol-keyed policy values.
    #
    # This intentionally preserves explicit false values.
    #
    # @param policy [Hash]
    # @param key [String, Symbol]
    # @return [Object, nil]
    def policy_value(policy, key)
      return nil unless policy.respond_to?(:[])

      return policy[key.to_s] if policy.respond_to?(:key?) && policy.key?(key.to_s)
      return policy[key.to_sym] if policy.respond_to?(:key?) && policy.key?(key.to_sym)

      nil
    end

    # Whether the cache response redirected away from its normalized URL.
    #
    # @return [Boolean]
    def redirected?
      Array(cache.redirect_chain).any? ||
        (cache.final_url.present? && cache.final_url.to_s != cache.normalized_url.to_s)
    end

    def primary_issue_for(issue_set)
      signaled_key = signal("primary_issue_key").presence
      return issue_set.primary if signaled_key.blank?

      issue_set.matches.find { |match| match[:key].to_s == signaled_key } || begin
        rule = Distillator::WringerRules.find(signaled_key)&.last || {}
        policy = rule["policy"] || rule[:policy] || {}
        {
          key: signaled_key.to_s,
          error_type: signal("primary_issue_error_code") || policy["error_code"] || policy[:error_code] || signaled_key.to_s,
          policy: policy,
          rule: rule,
          action: policy["action"] || policy[:action],
          retry: policy["retry"] || policy[:retry],
          cache: policy["cache"] || policy[:cache],
          delete: policy["delete"] || policy[:delete]
        }
      end
    end
  end
end
