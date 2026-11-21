require "cgi"
require "uri"

module Distillator
  module Cohorts
    class Matcher
      def self.match?(website, cohort_key)
        new(website).match?(cohort_key)
      end

      def self.memberships_for(website)
        new(website).memberships
      end

      def self.primary_membership_for(website)
        memberships_for(website).first
      end

      def self.normalize(value)
        new(nil).normalize(value)
      end

      def initialize(website)
        @website = website
      end

      def match?(cohort_key)
        cohort = Distillator::Cohorts::Registry.fetch(cohort_key)
        return false unless cohort

        cohort_tokens = normalize_all(cohort[:feed_names])
        website_tokens = normalized_website_tokens(cohort[:match_fields])

        (cohort_tokens & website_tokens).any?
      end

      def memberships
        Distillator::Cohorts::Registry.keys.filter_map do |cohort_key|
          cohort = Distillator::Cohorts::Registry.fetch(cohort_key)
          next unless cohort
          next unless match?(cohort_key)

          cohort.slice(:key, :label, :source_url)
        end
      end

      def normalize(value)
        raw = CGI.unescapeHTML(value.to_s).strip.downcase
        return nil if raw.blank?

        normalized = normalize_url_like(raw) || raw
        normalized = normalized.sub(/\Awww\./, "")
        normalized = normalized.gsub(/[._\/\s]+/, "-")
        normalized = normalized.gsub(/[^a-z0-9-]/, "-")
        normalized = normalized.gsub(/-+/, "-")
        normalized = normalized.gsub(/\A-|-+\z/, "")
        normalized.presence
      end

      private

      attr_reader :website

      def normalize_all(values)
        Array(values).filter_map { |value| normalize(value) }.uniq
      end

      def normalized_website_tokens(match_fields)
        Array(match_fields).flat_map do |field|
          website_values_for(field)
        end.then { |values| normalize_all(values) }
      end

      def website_values_for(field)
        return [] if website.blank?

        case field.to_s
        when "seedurl"
          [website.try(:seedurl)]
        when "name"
          [website.try(:name)]
        when "code"
          [
            website.try(:code),
            website.try(:seedurl),
            website.try(:graph_name)
          ]
        else
          [website.try(field)]
        end.compact
      end

      def normalize_url_like(value)
        parsed = URI.parse(value)
        host = parsed.host.presence || parsed.path.to_s
        host.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
      rescue URI::InvalidURIError
        return value.sub(/\Ahttps?:\/\//, "") if value.start_with?("http://", "https://")

        nil
      end
    end
  end
end
