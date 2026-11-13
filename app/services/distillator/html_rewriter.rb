require "cgi"
require "nokogiri"
require "uri"

module Distillator
  class HtmlRewriter
    PLACEHOLDER_PREFIX = "__distillator_absolute_attr__".freeze

    def self.absolute_src(html, url)
      new(html, url).absolute_src
    end

    def initialize(html, url)
      @html = html.to_s
      @url = url.to_s
    end

    def absolute_src
      fragment = Nokogiri::HTML::DocumentFragment.parse(html)
      base_url = resolved_base_url(fragment)
      passthroughs = {}

      rewrite_attributes(fragment, "src", base_url, passthroughs: passthroughs)
      rewrite_attributes(fragment, "href", base_url, passthroughs: passthroughs, exclude: ["base"])

      restore_passthrough_values(fragment.to_html, passthroughs)
    rescue StandardError => e
      Rails.logger.error("Error in Distillator::HtmlRewriter.absolute_src: #{e.inspect}")
      html
    end

    private

    attr_reader :html, :url

    def rewrite_attributes(fragment, attribute_name, base_url, passthroughs:, exclude: [])
      fragment.css("[#{attribute_name}]").each do |node|
        next if exclude.include?(node.name)

        value = node[attribute_name]
        next unless value.present?

        if passthrough_value?(value)
          placeholder = "#{PLACEHOLDER_PREFIX}#{passthroughs.length}__"
          passthroughs[placeholder] = value
          node[attribute_name] = placeholder
        else
          node[attribute_name] = absolute_url(value, base_url)
        end
      end
    end

    def resolved_base_url(fragment)
      base_href = fragment.at_css("base[href]")&.[]("href")
      return url if base_href.blank?

      absolute_url(base_href, url)
    end

    def absolute_url(value, base_url = url)
      value = value.to_s
      return value if value.blank?
      return value if passthrough_value?(value)

      if value.start_with?("//")
        scheme = URI.parse(base_url).scheme
        return value unless scheme.present?

        return "#{scheme}:#{value}"
      end

      URI.join(base_url, value).to_s
    rescue StandardError
      value
    end

    def passthrough_value?(value)
      CGI.unescapeHTML(value).match?(/\s/) ||
        value.match?(/%20/i) ||
        value.start_with?("#") ||
        value.start_with?("mailto:") ||
        value.start_with?("tel:") ||
        value.start_with?("data:")
    end

    def restore_passthrough_values(output, passthroughs)
      rewritten = output.to_s
      passthroughs.each do |placeholder, original|
        rewritten = rewritten.gsub(placeholder, original)
      end
      rewritten
    end
  end
end
