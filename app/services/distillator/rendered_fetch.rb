module Distillator
  class RenderedFetch
    def self.call(url:, uri_key:, iframe: false, headers: {}, timeout: nil, agent: nil, logger: nil)
      renderer.call(
        url: url,
        uri_key: uri_key,
        iframe: iframe,
        headers: headers,
        timeout: timeout,
        agent: agent,
        logger: logger || Rails.logger
      )
    end

    def self.renderer
      case ENV["DISTILLATOR_RENDERER"].to_s.presence || "legacy_phantomjs"
      when "legacy_phantomjs"
        Distillator::PhantomjsFetcher
      else
        Distillator::Renderers::DisabledRenderer
      end
    end

    private_class_method :renderer
  end
end
