module Distillator
  class HtmlContent
    BOMS = [["\x00\x00\xFE\xFF".b, "UTF-32BE"], ["\xFF\xFE\x00\x00".b, "UTF-32LE"],
      ["\xEF\xBB\xBF".b, "UTF-8"], ["\xFE\xFF".b, "UTF-16BE"], ["\xFF\xFE".b, "UTF-16LE"]].freeze

    # Non-binary strings with valid encodings are already decoded text. Only raw
    # bytes use BOM -> HTTP charset -> HTML meta charset -> validated UTF-8.
    # Never scrub/replace invalid bytes or mutate the caller's response.
    def self.decode(body, headers: {}, html: false)
      return body unless body.is_a?(String)

      type = Distillator::FetchService.normalize_headers(headers)[:content_type].to_s
      return body if !html && type.present? && !type.match?(/html/i)
      return body unless html || type.present? || html_prefix?(body.b) || BOMS.any? { |bom, _| body.b.start_with?(bom) }

      bom, bom_encoding = BOMS.find { |prefix, _| body.b.start_with?(prefix) }
      decoded = if body.encoding != Encoding::BINARY && body.valid_encoding?
        body.encode(Encoding::UTF_8).delete_prefix("\uFEFF")
      else
        source = Encoding.find(bom_encoding || charset(type) || meta_charset(body.b) || "UTF-8")
        bytes = bom ? body.b.byteslice(bom.bytesize..) : body.dup
        text = bytes.force_encoding(source)
        return body unless text.valid_encoding?

        text.encode(Encoding::UTF_8)
      end
      return body if !html && type.blank? && !html_prefix?(decoded.b)

      decoded
    rescue ArgumentError, EncodingError
      body
    end

    def self.title(body, headers: {})
      text = decode(body, headers: headers, html: true)
      return unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?

      normalize_text(Nokogiri::HTML(text, nil, "UTF-8").at_css("title")&.text).presence
    end

    def self.normalize_text(value, preserve_uris: false)
      text = value.to_s.gsub(/\s+/, " ").strip
      return text if preserve_uris && text.match?(/\A[a-z][a-z0-9+.-]*:/i)

      text.unicode_normalize(:nfc)
    end

    def self.charset(type)
      type[/\bcharset\s*=\s*["']?([^;"'\s]+)/i, 1]
    end

    def self.html_prefix?(bytes)
      bytes.match?(%r{\A\s*(?:<!--.*?-->\s*)*(?:<!doctype\s+html\b|<(?:html|head|body|title|meta|div|p)\b)}imn)
    end

    def self.meta_charset(bytes)
      # Encoding declarations belong in the first 1024 bytes. Strip comments so
      # a commented-out declaration cannot choose the decoder.
      bytes.byteslice(0, 1024).gsub(/<!--(?:.*?-->|.*\z)/mn, "").scan(/<meta\b[^>]*>/in).each do |tag|
        attributes = tag.scan(/([a-z][a-z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/in)
          .to_h { |key, *values| [key.downcase, values.compact.first] }
        return attributes["charset"] if attributes["charset"].present?
        if attributes["http-equiv"].to_s.downcase == "content-type"
          declared = charset(attributes["content"].to_s)
          return declared if declared.present?
        end
      end
      nil
    end

    private_class_method :charset, :html_prefix?, :meta_charset
  end
end
