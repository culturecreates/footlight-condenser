module Distillator
  class HtmlAbsolutizer
    def self.call(html:, base_url:)
      Distillator::HtmlRewriter.absolute_src(html, base_url)
    end
  end
end
