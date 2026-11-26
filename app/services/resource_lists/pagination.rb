module ResourceLists
  # Treat proven empty pagination tails as valid extraction. Only a successful
  # empty page before a later populated page requires completeness review.
  # Unrecognized URL shapes remain independent lists; no guessed ordering.
  class Pagination
    PAGE_PATH = %r{\A(.+)/page/(\d+)\z}i

    def self.review!(pages, evidence)
      pages_by_id = pages.index_by(&:id)
      groups = evidence.filter_map do |entry|
        page = pages_by_id[entry[:webpage_id]]
        signature = page && signature_for(page)
        [signature, entry] if signature
      end.group_by { |signature, _| signature.first }

      groups.each_value do |rows|
        next unless rows.size > 1 && rows.any? { |signature, _| signature.last }
        next unless rows.map { |signature, _| signature[1] }.uniq.size == rows.size

        ordered = rows.sort_by { |signature, _| signature[1] }
        last_populated = ordered.rindex { |_, entry| entry[:status] == "event" && entry[:count].to_i.positive? }
        next unless last_populated

        ordered.each_with_index do |(signature, entry), position|
          next unless entry[:status] == "event" && entry[:count] == 0

          trailing = position > last_populated
          entry[:pagination] = { page: signature[1], trailing_empty: trailing }
          next if trailing

          entry[:status] = "unverified"
          entry[:reason] = "pagination_gap"
          entry[:warning] = "A successfully empty page precedes a populated page in this pagination sequence."
        end
      end
      evidence
    end

    def self.signature_for(page)
      uri = Addressable::URI.parse(page.url.to_s)
      return unless uri.scheme.in?(%w[http https]) && uri.host.present? && uri.userinfo.nil?

      path = uri.path.to_s.sub(%r{/+\z}, "")
      match = PAGE_PATH.match(path)
      params = uri.query_values(Array) || []
      query_page = params.find { |key, _| key.to_s.downcase == "page" }
      return if match && query_page # Ambiguous pagination representation.

      explicit = match.present? || query_page.present?
      position = match ? match[2].to_i : (query_page ? Integer(query_page.last, 10) : 0)
      return if position.negative?

      base_path = match ? match[1] : path
      other_query = params.reject { |key, _| key.to_s.downcase == "page" }.sort
      key = [page.website_id, page.discovery_target_website_id, page.language,
        uri.scheme, uri.host.downcase.delete_prefix("www."), uri.port, base_path, other_query]
      [key, position, explicit]
    rescue Addressable::URI::InvalidURIError, ArgumentError, TypeError
      nil
    end

    private_class_method :signature_for
  end
end
