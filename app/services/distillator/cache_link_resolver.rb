require "cgi"

module Distillator
  class CacheLinkResolver
    # Operator-facing cache links use the rollout glossary in docs/rollout_modes.md.
    def self.call(url:, include_fragment: false, mode: nil, website: nil, website_id: nil, scrape_options: {})
      new(
        url: url,
        include_fragment: include_fragment,
        mode: mode,
        website: website,
        website_id: website_id,
        scrape_options: scrape_options
      ).call
    end

    def initialize(url:, include_fragment: false, mode: nil, website: nil, website_id: nil, scrape_options: {})
      @url = url
      @include_fragment = include_fragment
      @mode = mode&.to_sym
      @website = website
      @website_id = website_id
      @scrape_options = scrape_options.is_a?(Hash) ? scrape_options : {}
    end

    def call
      key = Distillator::WringerUrlKey.call(url, include_fragment: include_fragment)
      resolution = current_resolution
      legacy_url = "#{wringer_base_url}/websites?term=#{CGI.escape(key.uri_key)}"
      distillator_url = "/condenser/cache?term=#{CGI.escape(key.normalized_url)}"
      compare_url = "/condenser/cache/compare?uri=#{CGI.escape(url.to_s)}#{include_fragment_query}"

      payload = {
        mode: resolution.rollout_mode,
        rollout_mode: resolution.rollout_mode,
        active_backend: resolution.active_backend,
        source: resolution.source,
        legacy_uri_key: key.uri_key,
        distillator_uri_key: key.uri_key,
        legacy_cache_url: legacy_url,
        distillator_cache_url: distillator_url,
        compare_url: compare_url,
        active_cache_url: nil,
        label: Distillator::RolloutCopy.active_cache_label,
        secondary_links: [],
        warning: nil,
        disabled: false
      }

      case resolution.rollout_mode
      when :active
        payload[:active_cache_url] = distillator_url
        payload[:secondary_links] = [
          { label: Distillator::RolloutCopy.legacy_inspection_label, url: legacy_url },
          { label: Distillator::RolloutCopy.compare_label, url: compare_url }
        ]
      when :shadow
        payload[:active_cache_url] = legacy_url
        payload[:secondary_links] = [
          { label: Distillator::RolloutCopy.compare_label, url: compare_url },
          { label: Distillator::RolloutCopy.condenser_cache_label, url: distillator_url }
        ]
        payload[:warning] = Distillator::RolloutCopy.description(:shadow)
      when :replay
        payload[:active_cache_url] = distillator_url
        payload[:secondary_links] = [{ label: Distillator::RolloutCopy.legacy_inspection_label, url: legacy_url }]
        payload[:warning] = Distillator::RolloutCopy.description(:replay)
      else
        payload[:active_cache_url] = legacy_url
        payload[:secondary_links] = [{ label: Distillator::RolloutCopy.condenser_cache_label, url: distillator_url }]
        payload[:warning] = Distillator::RolloutCopy.description(:legacy)
      end

      payload
    rescue StandardError
      {
        mode: Distillator::RolloutCopy.normalize(mode || current_resolution.rollout_mode),
        rollout_mode: current_resolution.rollout_mode,
        active_backend: current_resolution.active_backend,
        source: current_resolution.source,
        legacy_uri_key: nil,
        distillator_uri_key: nil,
        legacy_cache_url: nil,
        distillator_cache_url: nil,
        active_cache_url: nil,
        label: Distillator::RolloutCopy.active_cache_label,
        secondary_links: [],
        warning: "",
        disabled: true
      }
    end

    private

    attr_reader :url, :include_fragment, :mode, :website, :website_id, :scrape_options

    def current_resolution
      Distillator::FetchMode.rollout_resolution_object(
        explicit_mode: mode,
        website: website,
        website_id: website_id
      )
    end

    def wringer_base_url
      ApplicationController.helpers.get_wringer_url_per_environment
    end

    def include_fragment_query
      include_fragment ? "&include_fragment=true" : ""
    end
  end
end
