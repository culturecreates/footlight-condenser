require "digest/sha1"
require "json"

module Distillator
  module ExportFetchModeHarness
    FIXTURE_STATEMENT_TIMESTAMP = Time.zone.parse("2026-04-27T00:00:00Z")

    FetchModeResponse = Struct.new(:code, :body, :uri, :response, keyword_init: true) do
      def [](key)
        response && (response[key] || response[key.to_s])
      end

      def headers
        response
      end
    end

    FetchModeHistoryEntry = Struct.new(:uri, keyword_init: true)

    class ReplayBackedWringerAgent
      attr_reader :fetched_urls

      def initialize(site:)
        @site = site
        @fetched_urls = []
        @history = []
      end

      def get(url)
        @fetched_urls << url
        payload = replay_payload(url)
        response = payload.fetch("response")
        @history = Array(response.fetch("redirect_chain")).map do |history_url|
          FetchModeHistoryEntry.new(uri: URI(history_url))
        end

        FetchModeResponse.new(
          code: http_code(response),
          body: response.fetch("body"),
          uri: URI(response.fetch("final_url") || url),
          response: response.fetch("headers")
        )
      end

      def history
        @history
      end

      private

      def replay_payload(url)
        path = Rails.root.join(
          "data",
          "migration_fixtures",
          @site,
          "fetch",
          "#{Digest::SHA1.hexdigest(url)}.json"
        )
        JSON.parse(File.read(path))
      end

      def http_code(response)
        wringer_code = response.dig("wringer", "http_code")
        return wringer_code.to_i if wringer_code
        return 404 if response.fetch("status") == "abort"

        200
      end
    end

    def run_export_under_fetch_mode(mode)
      reset_export_state!
      responses = fetch_curated_pages(mode)

      {
        responses: responses,
        export: ExportArtsdataService.call(seedurl: @fixture.fetch("seedurl"))
      }
    end

    def fetch_curated_pages(mode)
      @fixture.fetch("pages").index_by { |page| page.fetch("case") }.transform_values do |page|
        fetch_fixture_page(mode: mode, url: page.fetch("url"))
      end
    end

    def fetch_fixture_page(mode:, url:)
      case mode
      when :replay
        with_replay_fetch_enabled do
          Distillator::FetchService.fetch(url: url)
        end
      when :legacy
        with_fetch_replay_disabled do
          Distillator::FetchService.stubs(:use_internal_fetch?).returns(false)
          Distillator::FetchService.fetch(**wringer_fetch_kwargs(url))
        end
      when :internal
        with_fetch_replay_disabled do
          Distillator::FetchService.stubs(:use_internal_fetch?).returns(true)
          Distillator::FetchService.fetch(**wringer_fetch_kwargs(url))
        end
      else
        raise ArgumentError, "Unsupported fetch mode: #{mode.inspect}"
      end
    end

    def wringer_fetch_kwargs(url)
      {
        url: url,
        render_js: false,
        scrape_options: {},
        agent: ReplayBackedWringerAgent.new(site: self.class::FIXTURE_SITE),
        use_wringer: ->(resolved_url, _render_js, _scrape_options) { resolved_url },
        safe_wringer_call: method(:replay_wringer_policy),
        logger: Rails.logger
      }
    end

    def replay_wringer_policy(normalize_response: false)
      response = yield
      return response unless response.respond_to?(:code)

      case response.code.to_i
      when 404
        [
          "abort_update",
          {
            error: "Not Found",
            error_type: "http_404",
            source: "wringer",
            policy: { action: "abort_update", retry: false, cache: false }
          }
        ]
      else
        response
      end
    end

    def with_fetch_replay_disabled
      old_replay_fetch = ENV["REPLAY_FETCH"]
      old_fetch_site = ENV["FETCH_SITE"]
      ENV["REPLAY_FETCH"] = nil
      ENV["FETCH_SITE"] = nil
      yield
    ensure
      ENV["REPLAY_FETCH"] = old_replay_fetch
      ENV["FETCH_SITE"] = old_fetch_site
    end

    def with_replay_fetch_enabled
      old_replay_fetch = ENV["REPLAY_FETCH"]
      old_fetch_site = ENV["FETCH_SITE"]
      ENV["REPLAY_FETCH"] = "true"
      ENV["FETCH_SITE"] = self.class::FIXTURE_SITE
      yield
    ensure
      ENV["REPLAY_FETCH"] = old_replay_fetch
      ENV["FETCH_SITE"] = old_fetch_site
    end

    def reset_export_state!
      Distillator::FetchCache.delete_all
      Statement.where(status_origin: "distillator_export_invariance").update_all(
        cache_refreshed: FIXTURE_STATEMENT_TIMESTAMP,
        cache_changed: FIXTURE_STATEMENT_TIMESTAMP
      )
    end
  end
end
