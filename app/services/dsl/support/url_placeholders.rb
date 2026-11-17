module Dsl
  module Support
    class UrlPlaceholders
      TOKEN = "$$SELF_URL$$".freeze

      def self.expand(value)
        return value unless value.include?(TOKEN)
        origin = ENV["CONDENSER_PUBLIC_URL"].to_s.strip
        raise ArgumentError, "$$SELF_URL$$ requires CONDENSER_PUBLIC_URL for this environment" if origin.empty?
        uri = URI.parse(origin)
        unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? &&
          uri.fragment.nil? && ["", "/"].include?(uri.path)
          raise ArgumentError, "CONDENSER_PUBLIC_URL must be an HTTP(S) origin without credentials, path, query or fragment"
        end
        value.gsub(TOKEN) { origin.delete_suffix("/") }
      rescue URI::InvalidURIError
        raise ArgumentError, "CONDENSER_PUBLIC_URL is not a valid HTTP(S) origin"
      end
    end
  end
end
