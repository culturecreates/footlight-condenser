module Distillator
  class WebpageOperationEvidence
    FETCH_COLUMNS = %i[id uri_key scrape_date successful_refresh http_response_code health_status signals].freeze

    def self.for_pages(pages, as_of: Time.current, discovery_only: false, details: discovery_only)
      for_urls(pages.to_h { |page| [page.id, page.url] }, as_of: as_of, discovery_only: discovery_only, details: details)
    end

    def self.for_urls(urls, as_of: Time.current, discovery_only: false, details: discovery_only)
      ids = urls.keys
      return {} if ids.empty?

      keys = urls.transform_values { |url| cache_key(url) }
      caches = FetchCache.where(uri_key: keys.values.compact.uniq).select(*FETCH_COLUMNS).index_by(&:uri_key)
      statements = if discovery_only
        TransitionEventInventory.discovery_scope(ids).where(selected_individual: true, sources: { selected: true })
      else
        Statement.where(webpage_id: ids)
      end
      # Read only timestamps for the Webpages table. ResourceList details also explain extraction attempts.
      statements = if details
        statements.where(manual: [false, nil]).pluck(:webpage_id, :status, :cache_refreshed, :fetch_provenance, :source_id).group_by(&:first)
      else
        automatic = statements.where(manual: [false, nil])
        successes = automatic.where(status: Webpage::PUBLISHABLE_STATUSES)
          .or(automatic.where(status: "initial").where("fetch_provenance #>> '{saved,result}' = 'saved'"))
          .group(:webpage_id).maximum(:cache_refreshed)
        ids.to_h { |id| [id, [[id, "ok", successes[id], nil]]] }
      end

      keys.to_h do |id, key|
        [id, { fetch: fetch_evidence(caches[key], as_of), extraction: extraction_evidence(statements.fetch(id, [])) }]
      end
    end

    def self.cache_key(url)
      return unless url.to_s.match?(%r{\Ahttps?://}i)

      WringerUrlKey.call(url, include_fragment: true).uri_key
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
      nil
    end

    def self.fetch_evidence(cache, as_of)
      success = cache&.successful_refresh
      attempted = cache&.scrape_date
      state = if attempted && (success.nil? || attempted > success)
        :failed
      elsif success.nil?
        :unknown
      elsif success < as_of - TransitionEventInventory::MAX_LIST_AGE
        :stale
      else
        :fresh
      end
      { state: state, last_success_at: success, last_attempt_at: attempted, cache_id: cache&.id,
        http_status: cache&.http_response_code,
        backend: cache&.signals&.dig("body_profile", "backend") || (cache&.signals&.dig("fetch_backend") if success && state != :failed),
        attempt_backend: cache&.signals&.dig("fetch_backend"), health: cache&.health_status }
    end

    def self.extraction_evidence(rows)
      successes = rows.filter_map do |_, status, at, proof|
        at if status.in?(Webpage::PUBLISHABLE_STATUSES) ||
          (status == "initial" && proof&.dig("saved", "result") == "saved")
      end
      attempts = rows.filter_map { |_, _, _, proof| proof&.dig("attempt") }
      failures = attempts.select { |attempt| attempt["result"] == "failed" }
      proofs = rows.filter_map do |_, _status, stamp, proof, source_id|
        saved = proof&.dig("saved")
        saved.merge(source_id: source_id) if saved && stamp && saved["recorded_at"] == stamp.utc.iso8601(6)
      end
      { last_success_at: successes.max, latest_attempt_failed: failures.any?,
        failed_primary_fetch: failures.any? { |attempt| attempt.dig("primary", "result") == "abort" },
        last_attempt_at: attempts.map { |attempt| attempt["recorded_at"] }.compact.max,
        failed_statements: rows.count { |_, status, _, proof| status == "problem" || proof&.dig("attempt", "result") == "failed" },
        primary_usage: proofs.filter_map { |proof| proof.dig("primary", "usage") }.uniq,
        saved_inputs: proofs }
    end

    private_class_method :cache_key, :fetch_evidence, :extraction_evidence
  end
end
