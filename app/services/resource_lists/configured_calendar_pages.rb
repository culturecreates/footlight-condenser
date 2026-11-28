# frozen_string_literal: true

require "uri"

module ResourceLists
  # Read-only, strictly scoped preflight of explicitly configured calendar pages.
  # Contiguous configured pages are not evidence that the live source has
  # no additional pages. Never invent missing ResourceLists or page URLs.
  # Default stays one-based for Danse Danse; zero-based sites opt in.
  class ConfiguredCalendarPages
    MAX_PAGES_PER_LANGUAGE = 25
    Page = Struct.new(:number, :url, keyword_init: true)
    Result = Struct.new(:pages, :errors, keyword_init: true) do
      def valid? = errors.empty?
    end

    def self.call(webpages:, root:, path:, first_page: 1)
      new(webpages: webpages, root: root, path: path, first_page: first_page).call
    end

    def initialize(webpages:, root:, path:, first_page:)
      raise ArgumentError, "first_page must be 0 or 1" unless [0, 1].include?(first_page)
      @webpages, @root, @path, @first_page = webpages, root, path, first_page
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
        max_page = @first_page + MAX_PAGES_PER_LANGUAGE - 1
        if position < @first_page || position > max_page
          errors << "Configured page #{position} is outside the allowed range #{@first_page}..#{max_page}"
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
        missing = (@first_page..pages.keys.max).to_a - pages.keys
        errors << "Missing configured pagination page(s): #{missing.join(', ')}" if missing.any?
      end
      Result.new(pages: pages.sort.to_h.values, errors: errors)
    end

    # Accept only a bare one-based root, ?page=N, or /page/N. A zero-based
    # site must configure ?page=0 explicitly to avoid root alias collisions.
    def position_for(uri, base_path)
      return nil if uri.fragment
      match = %r{\A#{Regexp.escape(base_path)}/page/(\d+)\z}i.match(uri.path.to_s.sub(%r{/+\z}, ""))
      params = URI.decode_www_form(uri.query.to_s)
      return nil if params.any? { |name, _| name != "page" }
      return nil if match && params.any?
      return nil if params.size > 1

      literal = match ? match[1] : params.first&.last
      return @first_page == 1 ? 1 : nil unless literal
      return nil unless literal.match?(/\A(?:0|[1-9]\d*)\z/)

      literal.to_i
    rescue ArgumentError
      nil
    end
    private :position_for
  end
end
