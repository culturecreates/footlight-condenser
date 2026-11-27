# app/services/dsl/identity/url_fallback.rb
module Dsl
  module Identity
    class UrlFallback
    def self.id(url)
      "u#{Digest::MD5.hexdigest(url.to_s)[0..10]}"
    end
    end
  end
end
