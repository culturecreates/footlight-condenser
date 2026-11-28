# frozen_string_literal: true

module ResourceLists
  # Diagnostic recognition of an HTML page shell whose events are loaded via AJAX.
  class AjaxPaginationShell
    Result = Struct.new(:shell_only, :endpoint, keyword_init: true) do
      def shell_only? = shell_only
    end

    def self.inspect(doc)
      container = doc.at_css(".event_pagination_content_wrapper")
      loader = doc.at_css("[data-pagination-ajax]")
      endpoint = loader&.[]("data-pagination-ajax")
      empty = container && container.element_children.empty? && container.text.strip.empty?
      Result.new(shell_only: !!(empty && endpoint && !endpoint.strip.empty?), endpoint: endpoint)
    end
  end
end
