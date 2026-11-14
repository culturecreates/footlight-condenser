module Distillator
  # Explicit, reversible scope decisions. Does not archive events or change
  # statements, caches, rollout modes, or any previously completed evidence.
  class TransitionExclusionReview
    class InvalidReview < StandardError; end

    def self.eligible_rows(run)
      return [] unless run&.status == "completed"

      details = run.transition_evidences.find_by(check_kind: "fetch_parity")&.details.to_h.with_indifferent_access
      return [] unless details[:fetch_basis] == "fresh_both"

      Array(details[:representative_url_results]).map { |row| row.to_h.with_indifferent_access }.select do |row|
        legacy = row[:legacy_fetch].to_h.with_indifferent_access
        row[:url].to_s.match?(/\Ahttps?:\/\//) && row[:attempted_condenser_fetch] == true && row[:fetch_status] == "failed" &&
          row[:condenser_fetch].to_h.with_indifferent_access[:cache_hit] == false &&
          row[:condenser_fetch].to_h.with_indifferent_access[:fetch_path].in?([nil, "native"]) &&
          [404, 410, "404", "410"].include?(row[:http_response_code]) &&
          row[:legacy_lookup_status] == "unreachable" && legacy[:response_http_code].to_i.between?(200, 299) &&
          legacy[:force_scrape] == true && [404, 410, "404", "410"].include?(legacy[:upstream_http_code])
      end
    end

    def self.create!(website:, run:, url:, reason:)
      website.with_lock do
        ensure_no_running_check!(website)
        unless run.website_id == website.id && website.latest_transition_run&.id == run.id && run.status == "completed"
          raise InvalidReview, "Review the latest completed check for this website before excluding a URL"
        end
        row = eligible_rows(run).find { |entry| entry[:url] == url }
        raise InvalidReview, "Both backends must have recorded fresh source HTTP 404 or 410 responses for this URL" unless row
        raise InvalidReview, "The webpage URL is no longer part of this website" unless website.webpages.exists?(url: url)
        raise InvalidReview, "This URL is already excluded" if website.transition_exclusions.active.exists?(url: url)

        website.transition_exclusions.create!(source_run: run, url: url, reason: reason.to_s.strip, recorded_evidence: row)
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
