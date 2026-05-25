module Distillator
  class InspectionLinks
    def self.call(url:, website: nil, payload: nil)
      new(url: url, website: website, payload: payload).call
    end

    def initialize(url:, website: nil, payload: nil)
      @url = url
      @website = website
      @payload = payload
    end

    def call
      links = []
      links << { label: "Source website", url: url } if url.present?
      links << { label: "Compare", url: payload[:compare_url] } if payload[:compare_url].present?
      links << { label: payload[:label], url: payload[:active_cache_url] } if payload[:label].present? && payload[:active_cache_url].present?

      Array(payload[:secondary_links]).each do |link|
        next if link[:label].blank? || link[:url].blank?
        next if link[:url] == payload[:compare_url]

        links << { label: link[:label], url: link[:url] }
      end

      links << { label: "Webpage record", url: helpers.webpage_path(webpage) } if webpage.present?
      links.uniq { |link| [link[:label], link[:url]] }
    end

    private

    attr_reader :url, :website

    def payload
      @payload ||= Distillator::CacheLinkResolver.call(url: url, website: website)
    end

    def webpage
      @webpage ||= website&.webpages&.find_by(url: url)
    end

    def helpers
      Rails.application.routes.url_helpers
    end
  end
end
