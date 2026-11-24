require "json"
require "time"

module Distillator
  # An unavailable or ambiguous discovery list cannot establish that an event
  # was retired. Use the same site's selected discovery and date statements.
  class TransitionEventInventory
    MAX_LIST_AGE = 48.hours
    MAX_LIST_REFRESH_SKEW = 10.minutes
    DISCOVERY_LABELS = [AddWebpagesJob::RDF_CLASS_LABEL, AddWebpagesJob::URI_LIST_LABEL, AddWebpagesJob::WEBPAGE_URL_LIST_LABEL].freeze
    DATE_LABELS = ["Dates", "End Date"].freeze
    START_DATE_URIS = %w[schema:startDate http://schema.org/startDate https://schema.org/startDate].freeze
    END_DATE_URIS = %w[schema:endDate http://schema.org/endDate https://schema.org/endDate].freeze
    Result = Struct.new(:status, :lists, :retired, :valid_until, keyword_init: true)

    def self.statement_scope(website, class_name)
      Statement.joins(source: :property)
        .where(webpage_id: website.webpages.joins(:rdfs_class).where(rdfs_classes: { name: class_name }).select(:id))
        .where(sources: { website_id: website.id })
        .where("statements.selected_individual = TRUE OR sources.selected = TRUE")
    end

    def self.discovery_scope(website)
      statement_scope(website, "ResourceList").where(properties: { label: DISCOVERY_LABELS })
    end

    def self.dates_scope(website)
      scope = statement_scope(website, "Event")
      scope.where(properties: { label: DATE_LABELS }).or(scope.where(properties: { uri: START_DATE_URIS + END_DATE_URIS }))
    end

    def self.fingerprint_inputs(website)
      return [] unless website.webpages.joins(:rdfs_class).where(rdfs_classes: { name: "ResourceList" }).exists?

      lists = discovery_scope(website)
      dates = dates_scope(website)
      cache_digest = Arel.sql("md5(COALESCE(statements.cache, ''))")
      fields = ["statements.id", "statements.webpage_id", "statements.source_id", "statements.status", cache_digest]
      [lists.order("statements.id").pluck(*fields, "statements.selected_individual", "statements.cache_refreshed", "statements.manual"),
        dates.order("statements.id").pluck(*fields)]
    end

    def initialize(website:, as_of:)
      @website = website
      @as_of = as_of
    end

    def call(events)
      pages = @website.webpages.joins(:rdfs_class).where(rdfs_classes: { name: "ResourceList" }).order(:id)
      return result("no_discovery_lists") if pages.empty?

      selected = self.class.discovery_scope(@website).includes(source: :property).group_by(&:webpage_id)
      lists = pages.map { |page| inventory_for(page, selected.fetch(page.id, [])) }
      return result("discovery_unverified", lists: lists) if lists.any? { |list| list[:status] == "unverified" }

      event_lists = lists.select { |list| list[:status] == "event" }
      return result("no_event_discovery", lists: lists) if event_lists.empty?

      urls = event_lists.flat_map { |list| list[:url_keys] }.to_set
      uris = event_lists.flat_map { |list| list[:rdf_uris] }.to_set
      registered_urls = @website.webpages.event_pages.pluck(:url).filter_map { |url| public_url_key(url) }.to_set
      unless urls.subset?(registered_urls)
        return result("discovery_pending_import", lists: lists)
      end

      date_rows = self.class.dates_scope(@website)
        .where(webpage_id: events.reselect(:id)).includes(source: :property).group_by(&:webpage_id)
      retired = events.pluck(:id, :url, :rdf_uri).filter_map do |id, url, rdf_uri|
        key = public_url_key(url)
        next unless key && !urls.include?(key) && !uris.include?(rdf_uri)

        ended_at = last_occurrence(date_rows.fetch(id, []))
        next unless ended_at && ended_at < @as_of.beginning_of_day

        { webpage_id: id, url: url, last_occurrence: ended_at.iso8601 }
      end
      valid_until = event_lists.map { |list| list[:valid_until] }.min
      result("confirmed_discovery", lists: lists, retired: retired, valid_until: valid_until)
    end

    private

    def result(status, lists: [], retired: [], valid_until: nil)
      Result.new(status: status, retired: retired, valid_until: valid_until,
        lists: lists.map { |list| list.except(:url_keys, :rdf_uris, :valid_until) })
    end

    def inventory_for(page, selected)
      metadata = { webpage_id: page.id, url: page.url, status: "unverified" }
      by_label = selected.group_by { |statement| statement.source.property.label }
      target = only_statement(by_label, AddWebpagesJob::RDF_CLASS_LABEL)
      return metadata.merge(reason: "invalid_discovery_class") unless current_statement?(target)
      target_class = target.cache.to_s.strip
      if target_class != "Event"
        # A fixed data-only/non-event list has no say in event inventory.
        if target.manual? && (target_class == AddWebpagesJob::DATA_ONLY_CLASS || RdfsClass.exists?(name: target_class))
          return metadata.merge(status: "other_class")
        end
        return metadata.merge(reason: "invalid_discovery_class")
      end

      url_list = only_statement(by_label, AddWebpagesJob::WEBPAGE_URL_LIST_LABEL)
      uri_list = only_statement(by_label, AddWebpagesJob::URI_LIST_LABEL)
      return metadata.merge(reason: "ambiguous_list") unless [url_list, uri_list].all? { |statement| current_statement?(statement) && !statement.manual? }

      url_keys = string_array(url_list.cache)&.map { |url| public_url_key(url) }
      rdf_uris = string_array(uri_list.cache)
      unless url_keys.present? && rdf_uris.present? && url_keys.size == rdf_uris.size && url_keys.none?(&:nil?)
        return metadata.merge(reason: "invalid_or_empty_list")
      end

      timestamps = [target, url_list, uri_list].reject(&:manual?).map(&:cache_refreshed)
      changed_at = [page.created_at, page.updated_at].compact.max
      earliest = [@as_of - MAX_LIST_AGE, changed_at].compact.max
      unless timestamps.all? { |stamp| stamp && stamp.between?(earliest, @as_of) } &&
          timestamps.max - timestamps.min <= MAX_LIST_REFRESH_SKEW
        return metadata.merge(reason: "stale_or_unpaired_list")
      end

      metadata.merge(status: "event", refreshed_at: timestamps.min.iso8601, count: url_keys.size,
        url_keys: url_keys, rdf_uris: rdf_uris, valid_until: timestamps.min + MAX_LIST_AGE)
    end

    def only_statement(by_label, label)
      rows = by_label.fetch(label, [])
      rows.first if rows.one?
    end

    def current_statement?(statement)
      return false unless statement && Webpage::PUBLISHABLE_STATUSES.include?(statement.status) && statement.cache.present?
      return false unless statement.selected_individual? && statement.source.selected?
      return statement.source.algorithm_value.to_s.strip == "manual=#{statement.cache.to_s.strip}" if statement.manual?

      stamp = statement.cache_refreshed
      stamp && [statement.source.updated_at, statement.source.property.updated_at].compact.all? { |changed| stamp >= changed }
    end

    def string_array(cache)
      value = JSON.parse(cache.to_s)
      value if value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) && entry.present? }
    rescue JSON::ParserError
      nil
    end

    def last_occurrence(statements)
      ends, starts = statements.partition do |statement|
        property = statement.source.property
        property.label == "End Date" || END_DATE_URIS.include?(property.uri)
      end
      start = starts.first if starts.one?
      return unless start && Webpage::PUBLISHABLE_STATUSES.include?(start.status)

      dates = event_times(start.cache)
      return unless dates.present?

      return if ends.size > 1
      if (finish = ends.first)
        return unless Webpage::PUBLISHABLE_STATUSES.include?(finish.status)

        ending_dates = event_times(finish.cache)
        return unless ending_dates

        dates += ending_dates
      end
      dates.max
    end

    def event_times(value)
      return if value.blank?

      parsed = value.start_with?("[", '"') ? JSON.parse(value) : value
      Array(parsed).map do |date|
        return unless date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?\z/)

        day = Date.iso8601(date[0, 10])
        date.length == 10 ? day.in_time_zone.end_of_day : Time.zone.iso8601(date)
      end
    rescue JSON::ParserError, ArgumentError
      nil
    end

    def public_url_key(value)
      uri = Addressable::URI.parse(value.to_s).normalize
      return unless uri.scheme.in?(%w[http https]) && uri.host.present? && uri.userinfo.nil?

      [uri.host.delete_prefix("www."), uri.port, uri.path.delete_suffix("/"), uri.query]
    rescue Addressable::URI::InvalidURIError, ArgumentError
      nil
    end
  end
end
