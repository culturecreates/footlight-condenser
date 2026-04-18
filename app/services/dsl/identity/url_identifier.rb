# app/services/dsl/identity/url_identifier.rb
module Dsl
  module Identity
    class UrlIdentifier
      def self.call(url, params = {})
        new(url, params).call
      end

      def initialize(url, params)
        @url = url
        @params = params
      end

      def call
        uri = begin
              URI.parse(@url)
            rescue StandardError
              nil
            end
        return clean(raw_last_segment(@url)) unless uri

        # query first
        q = Rack::Utils.parse_query(uri.query)
        return q["id"] || q["eventId"] || q["eid"] if q["id"] || q["eventId"] || q["eid"]
        domain_id = extract_from_domain(uri)
        return domain_id if domain_id.present?

        segments = uri.path.split('/').reject(&:blank?)
        return nil if segments.empty?

        extract_from_path(segments)
      end

      private

      def clean(id)
        id.gsub(/\?.*/, "")
          .gsub(/\.html?$/, "")
      end

      def extract_from_path(segments)
        candidate = segments.reverse.find do |seg|
          valid_identifier_segment?(seg)
        end
        return clean(candidate) if candidate.present?

        last = segments.last.to_s
        return nil if blacklist.include?(last.downcase)

        clean(last)
      end

      def extract_from_domain(uri)
        host = uri.host.to_s
        path = uri.path.to_s

        if match_domain?(host, "lepointdevente")
          match = path[%r{/billets/([^/]+)}, 1].to_s
          return clean(match) if match.present?
        elsif match_domain?(host, "eventbrite")
          match = path[/-(\d+)(?:\D|$)/, 1].to_s
          return clean(match) if match.present?
        elsif match_domain?(host, "ticketweb")
          segments = path.split("/").reject(&:blank?)
          numeric = segments.reverse.find { |seg| seg.match?(/\A\d+\z/) }
          return clean(numeric.to_s) if numeric.present?
        end

        nil
      end

      def match_domain?(host, name)
        host == name || host.start_with?("#{name}.") || host.include?(".#{name}.")
      end

      def blacklist
        %w[show details index event events ticket tickets]
      end

      def valid_identifier_segment?(seg)
        normalized = seg.to_s.downcase
        (seg.to_s.match?(/\d/) || seg.to_s.length > 5) &&
          !blacklist.include?(normalized)
      end

      def raw_last_segment(url)
        url.to_s.split("?").first.to_s.split("/").reject(&:blank?).last.to_s
      end
    end
  end
end
