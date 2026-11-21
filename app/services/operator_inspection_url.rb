require "uri"

module OperatorInspectionUrl
  def self.normalize(value)
    uri = URI.parse(value.to_s.strip)
    return unless uri.is_a?(URI::HTTP) && uri.host.present? && !uri.userinfo && !uri.query && !uri.fragment

    uri.to_s.sub(%r{/+\z}, "")
  rescue URI::InvalidURIError
    nil
  end
end
