# frozen_string_literal: true

require "digest"
require "json"

module ResourceLists
  # Content-independent snapshot of anchor destinations. This is a diagnostic
  # for stalled pagers, not evidence that all event cards were extracted.
  module LinkInventory
    module_function

    def fingerprint(hrefs)
      raise ArgumentError, "expected href array" unless hrefs.is_a?(Array) &&
        hrefs.all? { |href| href.is_a?(String) }
      distinct = hrefs.map(&:strip).reject(&:empty?).uniq.sort
      return nil if distinct.empty?

      Digest::SHA256.hexdigest(JSON.generate(distinct))
    end
  end
end
