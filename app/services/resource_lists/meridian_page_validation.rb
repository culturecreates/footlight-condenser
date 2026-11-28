# frozen_string_literal: true

require "nokogiri"

module ResourceLists
  # Pure/read-only gate for Meridian calendar *audit* captures. A 200 response
  # is insufficient: verify that the HTML looks like a real navigable document.
  # The subsequent selected Source XPath still has to find valid event URLs.
  class MeridianPageValidation
    Invalid = Class.new(StandardError)
    Result = Struct.new(:title, :page_evidence, keyword_init: true)

    def self.call(html:)
      evidence = Distillator::PageEvidence.call(body: html)
      raise Invalid, "Content #{evidence.status}: #{evidence.reasons.join(', ')}" if evidence.flagged?

      document = Nokogiri::HTML(html.to_s)
      title = document.at_css("head title")&.text.to_s.squish
      raise Invalid, "Missing HTML page title" if title.empty?

      # Meridian may title the calendar after the theatre rather than using the
      # word Events. Reject obvious non-calendar shells using combined evidence,
      # not a single English/French title keyword.
      heading = document.at_css("main h1, h1")&.text.to_s.squish
      links = document.css("a[href]")
      navigation = document.css("nav, header, footer, [role=navigation]").any?
      if links.length < 5 || (!navigation && heading.empty?)
        raise Invalid, "Calendar document lacks expected navigation/link structure"
      end

      Result.new(title: title, page_evidence: evidence.to_signals)
    end
  end
end
