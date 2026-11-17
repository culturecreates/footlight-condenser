module Dsl
  module Support
    class UrlPlaceholders
      TOKEN = "$$SELF_URL$$".freeze

      def self.expand(value)
        return value unless value.include?(TOKEN)
        origin = self_origin.to_s.strip
        raise ArgumentError, "$$SELF_URL$$ could not identify this app; set CONDENSER_PUBLIC_URL for this environment" if origin.empty?
        uri = URI.parse(origin)
        unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? &&
          uri.fragment.nil? && ["", "/"].include?(uri.path)
          raise ArgumentError, "CONDENSER_PUBLIC_URL must be an HTTP(S) origin without credentials, path, query or fragment"
        end
        value.gsub(TOKEN) { origin.delete_suffix("/") }
      rescue URI::InvalidURIError
        raise ArgumentError, "CONDENSER_PUBLIC_URL is not a valid HTTP(S) origin"
      end
      def self.self_origin
        return ENV["CONDENSER_PUBLIC_URL"] if ENV["CONDENSER_PUBLIC_URL"].present?
        if ENV["HEROKU_APP_DEFAULT_DOMAIN_NAME"].present?
          return "https://#{ENV['HEROKU_APP_DEFAULT_DOMAIN_NAME']}"
        end
        if Distillator::TransitionRuntime.staging? || Distillator::TransitionRuntime.app_names.include?("footlight-condenser-test")
          return "https://footlight-condenser-test-c24c162bb7c8.herokuapp.com"
        end
        return "https://footlight-condenser.herokuapp.com" if Rails.env.production?
        return "http://localhost:3000" if Rails.env.development?
        nil
      end
      private_class_method :self_origin
    end
  end
end
