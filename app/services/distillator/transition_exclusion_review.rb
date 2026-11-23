module Distillator
  # Explicit, reversible scope decisions. Does not archive events or change
  # statements, caches, rollout modes, or any previously completed evidence.
  class TransitionExclusionReview
    class InvalidReview < StandardError; end

    def self.eligible_rows(run)
      return [] unless run&.status == "completed"

      details = run.transition_evidences.to_a.find { |record| record.check_kind == "fetch_parity" }&.details.to_h.with_indifferent_access
      return [] unless details[:fetch_basis] == "fresh_both"

      Array(details[:representative_url_results]).map { |row| row.to_h.with_indifferent_access }.select do |row|
        shared_source_missing?(row)
      end
    end

    def self.shared_source_missing?(row)
      legacy = row[:legacy_fetch].to_h.with_indifferent_access
      condenser = row[:condenser_fetch].to_h.with_indifferent_access
      row[:url].to_s.match?(/\Ahttps?:\/\//) && row[:attempted_condenser_fetch] == true && row[:fetch_status] == "failed" &&
        condenser[:cache_hit] == false && condenser[:fetch_path].in?([nil, "native"]) &&
        row[:http_response_code].to_s.in?(%w[404 410]) &&
        row[:legacy_lookup_status] == "unreachable" && legacy[:response_http_code].to_i.between?(200, 299) &&
        legacy[:force_scrape] == true && legacy[:upstream_http_code].to_s.in?(%w[404 410])
    end

    def self.create!(website:, run:, url:, reason:)
      create_many!(website: website, run: run, urls: [url], reason: reason).sole
    end

    def self.create_many!(website:, run:, urls:, reason:)
      unless urls.is_a?(Array) && urls.any? && urls.all? { |url| url.is_a?(String) && url.present? }
        raise InvalidReview, "Select at least one verified source URL"
      end
      urls = urls.uniq
      website.with_lock do
        ensure_no_running_check!(website)
        unless run.website_id == website.id && website.latest_transition_run&.id == run.id && run.status == "completed"
          raise InvalidReview, "Review the latest completed check for this website before excluding a URL"
        end
        rows = eligible_rows(run).index_by { |entry| entry[:url] }
        unless (urls - rows.keys).empty?
          raise InvalidReview, "Both backends must have recorded fresh source HTTP 404 or 410 responses for every selected URL"
        end
        present_urls = website.webpages.where(url: urls).distinct.pluck(:url)
        raise InvalidReview, "A webpage URL is no longer part of this website" unless (urls - present_urls).empty?
        raise InvalidReview, "A selected URL is already excluded" if website.transition_exclusions.active.where(url: urls).exists?

        # One transaction and one justification; each URL retains its own audit
        # evidence and can be independently restored. A bad selection saves none.
        urls.map do |url|
          website.transition_exclusions.create!(source_run: run, url: url, reason: reason.to_s.strip, recorded_evidence: rows.fetch(url))
        end
      end
    end

    def self.restore!(exclusion:, reason:)
      exclusion.website.with_lock do
        ensure_no_running_check!(exclusion.website)
        exclusion.reload
        raise InvalidReview, "This URL has already been restored" if exclusion.revoked_at

        exclusion.update!(revoked_at: Time.current, revocation_reason: reason.to_s.strip)
        exclusion
      end
    end

    def self.ensure_no_running_check!(website)
      if SiteTransition.active.where(website_id: website.id).exists?
        raise InvalidReview, "Wait for the validation workflow to finish before changing exclusions"
      end
      if website.transition_runs.active.where("requested_at > ?", Time.current - TransitionRun::LEASE).exists?
        raise InvalidReview, "Wait for the running transition check to finish before changing exclusions"
      end
    end
    private_class_method :ensure_no_running_check!
  end
end
