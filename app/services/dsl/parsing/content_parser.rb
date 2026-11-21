# app/services/dsl/parsing/content_parser.rb
module Dsl
  module Parsing
    class ContentParser
    def initialize(html: nil)
      @html = html
      @page = Nokogiri::HTML(html) if html
      @json_cache = nil
    end

    def parse_step(prefix, code, arr = [])
      case prefix
      when 'xpath'
        @page.xpath(code).map(&:text)

      when 'css'
        @page.css(code).map(&:text)

      when 'xpath_sanitize'
        @page.xpath(code).map do |node|
          frag = Nokogiri::HTML.fragment(node.to_s)

          # Remove disallowed content entirely (node + its children)
          frag.css('script, style').remove

          # Now sanitize allowed HTML
          sanitized_html =
            ActionController::Base.helpers.sanitize(
              frag.to_html,
              tags: %w[h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br],
              attributes: %w[href]
            )

          # Extract only visible text
          Nokogiri::HTML.fragment(sanitized_html).text.strip
        end.reject(&:empty?)

      when 'if_xpath'
        nodes = @page.xpath(code)
        nodes.blank? ? [] : nodes.map(&:text)

      when 'unless_xpath'
        nodes = @page.xpath(code)
        nodes.present? ? [] : arr

      when 'json'
        text = @html.to_s
        @json_cache ||= JSON.parse(text) # can raise JSON::ParserError
        evaluate_json_expr(code)

      when 'ruby'
        evaluate_ruby_expr(code, arr)

      when 'time_zone'
        ["time_zone: #{code}"]

      else
        raise "Missing DSL prefix: #{prefix}=#{code}"
      end
    end

    private

    def evaluate_json_expr(code)
      json = @json_cache
      binding.eval(code.to_s.sub('$json', 'json'))
    end

    def evaluate_ruby_expr(code, arr)
      array = arr
      binding.eval(code.to_s.sub('$array', 'array'))
    end

    end
  end
end
