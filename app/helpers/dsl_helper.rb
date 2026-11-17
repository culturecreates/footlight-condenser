module DslHelper
  # Presentation only: retain every character and delimiter, without expanding
  # library tokens, evaluating Ruby, or changing the DSL execution parser.
  def highlighted_dsl(algorithm)
    ruby_index = 0
    fragments = String.new(algorithm.to_s).split(/(;)/, -1).map do |step|
      if (token = step.match(/\A(\s*)(\$\$[A-Z][A-Z0-9_]*\$\$)(\s*)\z/))
        content_tag(:span, safe_join([token[1], content_tag(:strong, token[2], class: "dsl-instruction-prefix"), token[3]]),
          class: "dsl-instruction dsl-instruction--library")
      elsif (instruction = step.match(/\A(\s*)([a-z_]+)=/))
        kind = case instruction[2]
        when "ruby"
          ruby_index += 1
          ruby_index.odd? ? "ruby-a" : "ruby-b"
        when "xpath", "xpath_sanitize", "if_xpath", "unless_xpath", "css", "json", "sparql"
          "extraction"
        when "url", "renderjs_url", "post_url", "json_url", "api"
          "navigation"
        else
          "other"
        end
        content_tag(:span, safe_join([
          instruction[1], content_tag(:strong, "#{instruction[2]}=", class: "dsl-instruction-prefix"), step[instruction.end(0)..]
        ]), class: "dsl-instruction dsl-instruction--#{kind}")
      else
        step
      end
    end
    safe_join(fragments)
  end
end
