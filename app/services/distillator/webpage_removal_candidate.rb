# frozen_string_literal: true

module Distillator
  # Determines whether a Webpage may be removed after a Distillator refresh.
  #
  # This replaces the old Wringer cleanup path:
  #
  #   RefreshWebpageJob
  #     -> CcWringerHelper#wringer_received_404?
  #     -> live Wringer /websites.json?term=...
  #     -> delete based on Wringer-stored 404
  #
  # New Distillator cleanup path:
  #
  #   RefreshWebpageJob
  #     -> Distillator::RefreshRunner
  #     -> Distillator::WebpageRemovalCandidate.call(webpage)
  #     -> Distillator::WringerUrlKey.call(webpage.url)
  #     -> Distillator::FetchCache.find_by(uri_key: ...)
  #     -> Distillator::WringerRules.find(primary_issue_key)
  #     -> Result(delete:, reason:, cache:, policy:)
  #
  # Issue state is produced earlier by the fetch/cache pipeline:
  #
  #   FetchService
  #     -> WringerIssueSet / WringerSystemErrorMatcher
  #     -> config/wringer.yml
  #     -> FetchCacheStore
  #     -> CacheHealthMaterializer
  #     -> FetchCache issue fields
  #
  # Deletion is intentionally conservative. It requires:
  # - a matching FetchCache row;
  # - delete evidence from cache.delete_candidate or signals;
  # - YAML policy.delete == true;
  # - YAML policy.retry != true;
  # - no successful_refresh at or after scrape_date.
  #
  # This service is read-only. It does not fetch, call Wringer, parse HTML,
  # refresh records, or destroy webpages. The caller owns mutation:
  #
  #   result = Distillator::WebpageRemovalCandidate.call(webpage)
  #   webpage.destroy if result.delete?
  #
  class WebpageRemovalCandidate
    # Lightweight result object returned by .call.
    #
    # Fields:
    # - delete: Boolean; true only when the caller may delete the webpage.
    # - reason: Symbol explaining the decision.
    # - cache: The Distillator::FetchCache row used for the decision, if any.
    # - policy: The matched YAML policy hash, if any.
    Result = Struct.new(:delete, :reason, :cache, :policy, keyword_init: true) do
      def delete?
        delete == true
      end
    end

    # Evaluate deletion candidacy for a Webpage object or URL string.
    #
    # @param webpage_or_url [Webpage, String] object responding to #url, or a URL.
    # @param include_fragment [Boolean] whether URI-key generation should include URL fragments.
    # @return [Result]
    def self.call(webpage_or_url, include_fragment: false)
      new(webpage_or_url, include_fragment: include_fragment).call
    end

    # @param webpage_or_url [Webpage, String]
    # @param include_fragment [Boolean]
    def initialize(webpage_or_url, include_fragment:)
      @webpage_or_url = webpage_or_url
      @include_fragment = include_fragment
    end

    # Main decision entrypoint.
    #
    # Decision order matters:
    # - Missing cache means no evidence, so no delete.
    # - Missing delete policy means no delete, even if stale materialized data says otherwise.
    # - Retryable issues are preserved for later refresh attempts.
    # - Newer/same successful refresh prevents deleting valid content.
    #
    # @return [Result]
    def call
      return result(false, :missing_cache) unless cache

      policy = rule_policy

      return result(false, :not_delete_candidate, policy: policy) unless delete_policy?(policy)
      return result(false, :retryable_issue, policy: policy) if retryable_issue?(policy)
      return result(false, :newer_successful_refresh, policy: policy) if newer_successful_refresh?

      result(true, :delete_candidate, policy: policy)
    end

    private

    attr_reader :webpage_or_url, :include_fragment

    # Build a Result with the current cache attached.
    #
    # @param delete [Boolean]
    # @param reason [Symbol]
    # @param policy [Hash]
    # @return [Result]
    def result(delete, reason, policy: {})
      Result.new(delete: delete, reason: reason, cache: cache, policy: policy)
    end

    # Find the cache row by Wringer-compatible URI key.
    #
    # Invalid URLs are treated as "no usable evidence", not as errors.
    #
    # @return [Distillator::FetchCache, nil]
    def cache
      @cache ||= Distillator::FetchCache.find_by(uri_key: uri_key)
    rescue URI::InvalidURIError, Addressable::URI::InvalidURIError
      nil
    end

    # Compute the Wringer-compatible URI key for the source URL.
    #
    # @return [String]
    def uri_key
      @uri_key ||= Distillator::WringerUrlKey.call(url, include_fragment: include_fragment).uri_key
    end

    # Resolve a URL from either a Webpage-like object or a raw string.
    #
    # @return [String]
    def url
      webpage_or_url.respond_to?(:url) ? webpage_or_url.url : webpage_or_url.to_s
    end

    # Resolve the YAML policy for the cache's primary issue.
    #
    # Prefer the materialized column, but fall back to signals for partially
    # materialized rows created during migration.
    #
    # @return [Hash]
    def rule_policy
      rule = Distillator::WringerRules.find(primary_issue_key)&.last
      policy = rule && (rule["policy"] || rule[:policy])

      policy.respond_to?(:to_h) ? policy.to_h : {}
    end

    # Primary issue key used to look up config/wringer.yml policy.
    #
    # @return [String, nil]
    def primary_issue_key
      cache&.primary_issue_key.presence || signals[:primary_issue_key].presence
    end

    # A delete decision requires both:
    # - cache/signal evidence that this row was marked as a delete candidate; and
    # - current YAML policy allowing deletion.
    #
    # This protects against stale cache rows after YAML policy changes.
    #
    # @param policy [Hash]
    # @return [Boolean]
    def delete_policy?(policy)
      delete_candidate_evidence? && policy_value(policy, :delete) == true
    end

    # Detect delete-candidate evidence from materialized columns or signals.
    #
    # @return [Boolean]
    def delete_candidate_evidence?
      cache.delete_candidate == true || truthy_signal?(:primary_issue_delete)
    end

    # Retryable issues should not delete pages. Examples include waiting rooms,
    # captcha, Cloudflare, Akamai, timeout, and other transient fetch failures.
    #
    # @param policy [Hash]
    # @return [Boolean]
    def retryable_issue?(policy)
      policy_value(policy, :retry) == true
    end

    # Prevent deletion when the latest scrape was successful.
    #
    # successful_refresh is the latest successful content update.
    # scrape_date is the latest scrape attempt.
    #
    # If successful_refresh >= scrape_date, the latest scrape attempt either
    # succeeded or has been superseded by a successful refresh, so deleting would
    # be unsafe.
    #
    # @return [Boolean]
    def newer_successful_refresh?
      return false if cache.successful_refresh.blank?
      return false if cache.scrape_date.blank?

      cache.successful_refresh >= cache.scrape_date
    end

    # Cache signals as an indifferent-access hash.
    #
    # @return [ActiveSupport::HashWithIndifferentAccess]
    def signals
      @signals ||= (cache&.signals || {}).to_h.with_indifferent_access
    end

    # Interpret a signal boolean conservatively.
    #
    # Accepts true and common string/number encodings used in serialized JSON.
    #
    # @param key [Symbol, String]
    # @return [Boolean]
    def truthy_signal?(key)
      value = signals[key]
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    # Safely read string-keyed or symbol-keyed policy values.
    #
    # This intentionally preserves explicit false values.
    #
    # @param policy [Hash]
    # @param key [Symbol, String]
    # @return [Object, nil]
    def policy_value(policy, key)
      return nil unless policy.respond_to?(:[])

      return policy[key.to_s] if policy.respond_to?(:key?) && policy.key?(key.to_s)
      return policy[key.to_sym] if policy.respond_to?(:key?) && policy.key?(key.to_sym)

      nil
    end
  end
end