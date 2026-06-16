require "will_paginate/collection"

module Places
  class IndexQuery
    FILTER_KEYS = %i[seedurl term].freeze
    DEFAULT_SORT = "rdf_uri".freeze
    DEFAULT_DIRECTION = "asc".freeze
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    SORT_COLUMNS = %w[rdf_uri based_on linked_name linked_uri].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filters:, sort:, direction:, page:, per_page:)
      @filters = filters.to_h.symbolize_keys
      @sort = SORT_COLUMNS.include?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
      @page = page.to_i
      @per_page = per_page.to_i
    end

    def call
      rows = raw_places.flat_map { |place| normalize_place(place) }
      rows = filter_term(rows)
      rows = rows.sort_by { |row| row[sort].to_s.downcase }
      rows.reverse! if direction == "desc"
      paginate_rows(rows)
    end

    private

    attr_reader :filters, :sort, :direction, :page, :per_page

    def raw_places
      Statement
        .joins({ source: [:property, :website] }, :webpage)
        .where(
          sources: { selected: true },
          properties: { label: "Location", rdfs_class: 1 },
          websites: { seedurl: filters[:seedurl] }
        )
        .pluck(:rdf_uri, :cache, "sources.language", "webpages.url")
    end

    def normalize_place(place)
      rdf_uri, cache, language, based_on = place
      parsed = parse_cache(cache)
      entries = place_entries(parsed)

      entries.flat_map do |entry|
        if entry.is_a?(Array) && entry.first.is_a?(Array)
          entry.map { |subcache| build_row(rdf_uri, based_on, language, subcache) }
        else
          [build_row(rdf_uri, based_on, language, entry)]
        end
      end
    end

    def parse_cache(cache)
      JSON.parse(cache)
    rescue StandardError
      return cache.first.is_a?(Array) ? cache : [cache] if cache.is_a?(Array)

      [cache]
    end

    def place_entries(parsed)
      return [parsed] if single_place_entry?(parsed)

      Array(parsed)
    end

    def single_place_entry?(parsed)
      parsed.is_a?(Array) && parsed.any? && !parsed.first.is_a?(Array)
    end

    def build_row(rdf_uri, based_on, language, entry)
      values = Array(entry)
      linked_name = values.find { |value| value.is_a?(String) && value != based_on }
      links = values.find { |value| value.is_a?(Array) }
      linked_uri = Array(links)[1]
      {
        rdf_uri: rdf_uri,
        based_on: based_on,
        language: language,
        place_class: values[1].is_a?(String) ? values[1] : "Place",
        linked_name: linked_name.to_s,
        linked_uri: linked_uri.to_s
      }
    end

    def filter_term(rows)
      return rows unless filters[:term].present?

      term = filters[:term].downcase
      rows.select { |row| row.values.compact.join(" ").downcase.include?(term) }
    end

    def paginate_rows(rows)
      WillPaginate::Collection.create(page, per_page, rows.length) do |pager|
        pager.replace(rows[pager.offset, pager.per_page] || [])
      end
    end
  end
end
