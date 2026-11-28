# frozen_string_literal: true

require "uri"

module ResourceLists
  # Read-only, strictly scoped pagination preflight for Danse Danse's QA copy.
  # A contiguous configured page set is not evidence that the live source has
  # no additional pages. Never invent missing ResourceLists or page URLs.
  class ConfiguredCalendarPages
    MAX_PAGES_PER_LANGUAGE = 25
    Page = Struct.new(:number, :url, keyword_init: true)
    Result = Struct.new(:pages, :errors, keyword_init: true) do
      def valid? = errors.empty?
    end

    def self.call(webpages:, root:, path:)
      new(webpages: webpages, root: root, path: path).call
    end

    def initialize(webpages:, root:, path:)
      @webpages, @root, @path = webpages, root, path
    end

    def call
      root_uri = URI.parse(@root)
      raise ArgumentError, "Invalid calendar origin" unless root_uri.scheme == "https" && root_uri.host && root_uri.userinfo.nil?

      pages, errors = {}, []
      Array(@webpages).each do |webpage|
        next unless webpage.url.to_s.start_with?(@root)
        uri = URI.parse(webpage.url)
        next unless uri.scheme == root_uri.scheme && uri.host == root_uri.host && uri.port == root_uri.port

        normalized_path = uri.path.to_s.sub(%r{/+\z}, "")
        base_path = @path.sub(%r{/+\z}, "")
        next unless normalized_path == base_path || normalized_path.match?(%r{\A#{Regexp.escape(base_path)}/page/\d+\z}i)

        position = position_for(uri, base_path)
        if position.nil?
          errors << "Unrecognized or ambiguous calendar pagination URL: #{webpage.url}"
          next
        end
        if position < 1 || position > MAX_PAGES_PER_LANGUAGE
          errors << "Configured page #{position} is outside the allowed range 1..#{MAX_PAGES_PER_LANGUAGE}"
          next
        end
        if pages.key?(position)
          errors << "Duplicate calendar page #{position}: #{pages.fetch(position).url} and #{webpage.url}"
          next
        end
        pages[position] = Page.new(number: position, url: webpage.url)
      rescue URI::InvalidURIError, ArgumentError => error
        errors << "Invalid configured URL: #{error.class}"
      end

      if pages.empty?
        errors << "No configured ResourceLists for #{@path}"
      else
        missing = (1..pages.keys.max).to_a - pages.keys
        errors << "Missing configured pagination page(s): #{missing.join(', ')}" if missing.any?
      end
      Result.new(pages: pages.sort.to_h.values, errors: errors)
    end

    # Accept only a bare root, ?page=N, or /page/N. Do not mistake arbitrary
    # calendar filters for another page of the same inventory.
    def position_for(uri, base_path)
      match = %r{\A#{Regexp.escape(base_path)}/page/(\d+)\z}i.match(uri.path.to_s.sub(%r{/+\z}, ""))
      params = URI.decode_www_form(uri.query.to_s)
      return nil if params.any? { |name, _| name != "page" }
      return nil if match && params.any?
      return nil if params.size > 1

      literal = match ? match[1] : params.first&.last
      return 1 unless literal
      return nil unless literal.match?(/\A[1-9]\d*\z/)

      literal.to_i
    rescue ArgumentError
      nil
    end
    private :position_for
  end
end
