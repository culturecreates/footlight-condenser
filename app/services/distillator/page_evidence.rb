# frozen_string_literal: true

require "nokogiri"

module Distillator
  # Evaluate fetched *documents*, not lists of anti-bot vendors.
  # An unknown page is not automatically valid or a challenge. Only very
  # strong interstitial evidence or dramatic regressions are fail-closed.
  class PageEvidence
    MAX_BASELINE_BYTES = 4_000_000
    IDENTITY = /\b(?:pardon our interruption|verify (?:you are|you're) (?:a )?human|checking your browser|browser verification|security check|access denied|one moment,? please|just a moment|please stand by|unusual traffic)\b/i
    PROMPT = /\b(?:think you were a bot|thought you were a bot|verify (?:you are|you're) human|enable (?:your )?cookies and javascript|checking your browser|browser verification|unusual traffic|suspicious activity|security check|complete (?:the )?captcha)\b/i

    Result = Struct.new(:status, :reasons, :metrics, keyword_init: true) do
      def flagged?
        status != "observed"
      end

      def blocking_key
        { "rejected" => "generic_page_challenge", "unverified" => "page_structure_anomaly" }[status]
      end

      def to_signals
        { "page_validation_status" => status, "page_validation_reasons" => reasons,
          "page_validation_metrics" => metrics }
      end
    end

    def self.call(body:, baseline_html: nil)
      new(body: body, baseline_html: baseline_html).call
    end

    # Keep HTTP transport status separate from content acceptability.
    def self.annotate_result(result, evidence)
      return result unless evidence&.flagged?

      payload = result.deep_dup
      payload[:wringer] ||= {}
      wringer = payload[:wringer]
      signals = wringer.fetch(:signals, {}).to_h.stringify_keys
      signals.merge!(evidence.to_signals)
      signals["content_success"] = false
      signals["blocking_issue_key"] ||= evidence.blocking_key
      wringer[:signals] = signals
      wringer[:policy_action] = "abort_update"
      wringer[:retry] = true if wringer[:retry].nil?
      wringer[:cache] = false
      wringer[:hints] = (Array(wringer[:hints]) + [evidence.blocking_key] +
        (evidence.status == "rejected" ? ["blocked"] : [])).uniq
      payload
    end

    def initialize(body:, baseline_html:)
      @body = body
      @baseline_html = baseline_html
    end

    def call
      return Result.new(status: "observed", reasons: [], metrics: {}) unless html?(@body)
      return Result.new(status: "observed", reasons: [], metrics: {}) if @body.bytesize > MAX_BASELINE_BYTES

      current = fingerprint(@body)
      reasons = []
      if challenge_page?(current)
        reasons << "challenge_page_identity" if current[:identity]
        reasons << "browser_verification_text" if current[:prompt]
        reasons << "missing_site_navigation" if current[:sparse]
        reasons << "noindex_page" if current[:noindex]
        return Result.new(status: "rejected", reasons: reasons, metrics: public_metrics(current))
      end

      if html?(@baseline_html) && @baseline_html.bytesize <= MAX_BASELINE_BYTES
        previous = fingerprint(@baseline_html)
        reasons << "document_shrank" if previous[:bytes] >= 12_000 && current[:bytes] * 4 < previous[:bytes]
        reasons << "links_disappeared" if previous[:links] >= 12 && current[:links] * 5 < previous[:links]
        reasons << "navigation_disappeared" if previous[:layout] && !current[:layout]
        reasons << "dates_disappeared" if previous[:dates] >= 2 && current[:dates] == 0
        reasons << "page_identity_changed" if previous[:title].present? && current[:title].present? && previous[:title] != current[:title]
        # This may be a redesign, NOT necessarily a bot. Preserve the last-good
        # document until the operator verifies the new page.
        if reasons.include?("page_identity_changed") &&
            (reasons & %w[links_disappeared navigation_disappeared]).any? && reasons.length >= 3
          return Result.new(status: "unverified", reasons: reasons, metrics: public_metrics(current))
        end
      end

      Result.new(status: "observed", reasons: [], metrics: public_metrics(current))
    end

    private

    def html?(body)
      body.is_a?(String) && body.include?("<") && body.match?(/<(?:!doctype|html|head|body|title|div|main|section|h1)\b/i)
    end

    def fingerprint(body)
      doc = Nokogiri::HTML(body)
      title = doc.at_css("head title")&.text.to_s.squish
      heading = doc.at_css("body h1")&.text.to_s.squish
      robots = doc.css('meta[name="robots"], meta[name="googlebot"]').map { |m| m["content"].to_s.downcase }.join(" ")
      visible = doc.at_css("body") || doc
      text_only = visible.dup
      text_only.css("script, style, noscript, template, svg").remove
      visible_text = text_only.text.to_s.squish
      links = visible.css("a[href]").length
      navigation = visible.css("nav, footer, [role=navigation], [role=contentinfo]").any?
      dates = visible.css("time[datetime]").length + visible_text.scan(/\b20\d{2}[-\/]\d{1,2}[-\/]\d{1,2}\b/).size
      {
        bytes: body.bytesize, title: title.downcase, links: links, layout: navigation, dates: dates,
        identity: [title, heading].any? { |candidate| candidate.match?(IDENTITY) },
        prompt: visible_text.match?(PROMPT),
        noindex: robots.include?("noindex"),
        sparse: !navigation && links <= 3
      }
    end

    def challenge_page?(data)
      data[:sparse] && ((data[:identity] && (data[:prompt] || data[:noindex])) ||
        (data[:prompt] && data[:noindex] && data[:links] <= 1))
    end

    def public_metrics(data)
      data.slice(:bytes, :links, :layout, :dates)
    end
  end
end
