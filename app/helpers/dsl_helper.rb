module DslHelper
  DSL_HIGHLIGHT_KINDS = %w[xpath xpath_sanitize if_xpath unless_xpath css json sparql].index_with("extraction")
    .merge(%w[url renderjs_url post_url json_url api].index_with("navigation")).freeze

  def dsl_highlight_kinds
    DSL_HIGHLIGHT_KINDS
  end

  # Presentation only: retain every character and delimiter, without expanding
  # library tokens, evaluating Ruby, or changing the DSL execution parser.
  def highlighted_dsl(algorithm)
    safe_join(highlighted_dsl_steps(algorithm.to_s.split(/(;)/, -1)))
  end

  def highlighted_dsl_steps(steps)
    ruby_index = 0
    steps.map do |raw_step|
      step = String.new(raw_step)
      if (token = step.match(/\A(\s*)(\$\$[A-Z][A-Z0-9_]*\$\$)(\s*)\z/))
        content_tag(:span, safe_join([token[1], content_tag(:strong, token[2], class: "dsl-instruction-prefix"), token[3]]),
          class: "dsl-instruction dsl-instruction--library")
      elsif (instruction = step.match(/\A(\s*)([a-z_]+)=/))
        kind = if instruction[2] == "ruby"
          ruby_index += 1
          ruby_index.odd? ? "ruby-a" : "ruby-b"
        else
          dsl_highlight_kinds.fetch(instruction[2], "other")
        end
        content_tag(:span, safe_join([
          instruction[1], content_tag(:strong, "#{instruction[2]}=", class: "dsl-instruction-prefix"), step[instruction.end(0)..]
        ]), class: "dsl-instruction dsl-instruction--#{kind}")
      else
        step
      end
    end
  end
end
