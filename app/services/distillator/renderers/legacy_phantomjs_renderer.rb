require "json"

module Distillator
  module Renderers
    class LegacyPhantomjsRenderer
      def self.call(url:, uri_key:, iframe:, headers: {}, timeout: nil, agent: nil, logger: nil)
        Distillator::PhantomjsFetcher.call(url: url, uri_key: uri_key, iframe: iframe, headers: headers, timeout: timeout, agent: agent, logger: logger)
      end

      def self.request_url(url:, iframe:)
        Distillator::PhantomjsFetcher.request_url(url: url, iframe: iframe)
      end

      def self.extract_iframe_content(result)
        Distillator::PhantomjsFetcher.extract_iframe_content(result)
      end
    end
  end
end
