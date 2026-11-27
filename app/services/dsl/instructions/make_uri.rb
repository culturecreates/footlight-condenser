# app/services/dsl/instructions/make_uri.rb
module Dsl
  module Instructions
    class MakeUri
      def self.call(arr, code, context:)
        new(arr, code, context).call
      end

      def initialize(arr, code, context)
        @arr = arr || []
        @params = parse_params(code)
        @context = context
        @agent = context&.instance_variable_get(:@agent)
      end

      def call
        prefix = @params["prefix"] || default_prefix

        @arr.map do |url|
          build_uri(url, prefix) || fallback_uri(prefix, url)
        end
      end

      private

      def build_uri(url, prefix)
        return nil if url.blank?

        final_url = expand_url_if_needed(url)
        id = extract_best_id(final_url)
        id = fallback_id(final_url) if id.blank?

        "footlight:#{prefix}_#{normalize(id)}"
      end

      def expand_url_if_needed(url)
        return url unless needs_expansion?(url)

        Dsl::Network::UrlExpander.call(url, context: @context)
      end

      def extract_best_id(url)
        Dsl::Identity::UrlIdentifier.call(url, @params)
      end

      def fallback_id(url)
        Dsl::Identity::UrlFallback.id(url)
      end

      def fallback_uri(prefix, url)
        "footlight:#{prefix}_#{normalize(fallback_id(url))}"
      end

      def default_prefix
        seed =
          if @context.respond_to?(:[])
            @context[:seedurl] || @context["seedurl"]
          end

        normalize(seed.presence || "default")
      end

      def parse_params(code)
        return {} if code.blank?

        code.to_s.split(",").each_with_object({}) do |fragment, memo|
          key, value = fragment.split("=", 2).map { |part| part.to_s.strip }
          next if key.blank?

          memo[key] =
            case value&.downcase
            when "true" then true
            when "false" then false
            else value
            end
        end
      end

      def needs_expansion?(url)
        return true if @params["expand"] == true
        return false if @params["expand"] == false

        uri = URI.parse(url) rescue nil
        return false unless uri

        uri.host =~ /bit\.ly|t\.co|tinyurl|lpdv\.co/
      end

      def normalize(id)
        id.to_s.downcase
          .gsub(/[^a-z0-9]+/, "-").squeeze("-")
          .gsub(/^-|-$/, "")
      end
    end
  end
end
