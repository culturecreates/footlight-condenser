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
    Result = Struct.new(:status, :lists, :retired, :valid_until, :selected_event_urls_missing, keyword_init: true)

    def self.statement_scope(website_ids, class_name)
      Statement.joins(webpage: :rdfs_class, source: :property)
        .where(webpages: { website_id: website_ids }, rdfs_classes: { name: class_name })
        .where("sources.website_id = webpages.website_id")
        .where("statements.selected_individual = TRUE OR sources.selected = TRUE")
    end

    def self.discovery_scope(website_ids)
      statement_scope(website_ids, "ResourceList").where(properties: { label: DISCOVERY_LABELS })
    end

    def self.dates_scope(website_ids)
      scope = statement_scope(website_ids, "Event")
      scope.where(properties: { label: DATE_LABELS }).or(scope.where(properties: { uri: START_DATE_URIS + END_DATE_URIS }))
    end

    def self.fingerprint_inputs(website)
      return [] unless website.webpages.joins(:rdfs_class).where(rdfs_classes: { name: "ResourceList" }).exists?

      lists = discovery_scope(website.id)
      dates = dates_scope(website.id)
      cache_digest = Arel.sql("md5(COALESCE(statements.cache, ''))")
      fields = ["statements.id", "statements.webpage_id", "statements.source_id", "statements.status", cache_digest]
      [lists.order("statements.id").pluck(*fields, "statements.selected_individual", "statements.cache_refreshed", "statements.manual"),
        dates.order("statements.id").pluck(*fields)]
    end

    def initialize(as_of:)
      @as_of = as_of
    end

    def for_websites(website_ids, events:)
      pages = Webpage.joins(:rdfs_class).where(website_id: website_ids, rdfs_classes: { name: "ResourceList" }).order(:id)
        .group_by(&:website_id)
      results = website_ids.index_with { result("no_discovery_lists") }
      return results if pages.empty?

      selected = self.class.discovery_scope(pages.keys).includes(source: :property).group_by(&:webpage_id)
      class_names = RdfsClass.pluck(:name).to_set
      event_lists_by_site = {}
      pages.each do |website_id, lists|
        evidence = lists.map { |page| inventory_for(page, selected.fetch(page.id, []), class_names) }
        event_lists = evidence.select { |list| list[:status] == "event" }
        status = if evidence.any? { |list| list[:status] == "unverified" }
          "discovery_unverified"
        elsif event_lists.empty?
          "no_event_discovery"
        else
          event_lists_by_site[website_id] = event_lists
          "confirmed_discovery"
        end
        results[website_id] = result(status, lists: evidence, valid_until: event_lists.map { |list| list[:valid_until] }.min)
      end
      return results if event_lists_by_site.empty?

      missing_by_site = missing_event_rows(event_lists_by_site, events, results)
      missing_ids = missing_by_site.values.flat_map { |rows| rows.map(&:first) }
      date_rows = self.class.dates_scope(missing_by_site.keys)
        .where(webpage_id: missing_ids).includes(source: :property).group_by(&:webpage_id)
      missing_by_site.each do |website_id, rows|
        inventory = results.fetch(website_id)
        inventory.retired = rows.filter_map do |id, url|
          ended_at = last_occurrence(date_rows.fetch(id, []))
          { webpage_id: id, url: url, last_occurrence: ended_at.iso8601 } if ended_at && ended_at < @as_of.beginning_of_day
        end
        inventory.selected_event_urls_missing = rows.size - inventory.retired.size
      end
      results
    end

    private

    def missing_event_rows(event_lists_by_site, events, results)
      registered = Webpage.event_pages.where(website_id: event_lists_by_site.keys).pluck(:website_id, :url).group_by(&:first)
      candidates = events.where(website_id: event_lists_by_site.keys).pluck(:website_id, :id, :url, :rdf_uri).group_by(&:first)
      event_lists_by_site.each_with_object({}) do |(website_id, lists), missing|
        urls = lists.flat_map { |list| list[:url_keys] }.to_set
        imported = registered.fetch(website_id, []).filter_map { |_, url| public_url_key(url) }.to_set
        unless urls.subset?(imported)
          results.fetch(website_id).status = "discovery_pending_import"
          next
        end
        uris = lists.flat_map { |list| list[:rdf_uris] }.to_set
        missing[website_id] = candidates.fetch(website_id, []).filter_map do |_, id, url, rdf_uri|
          key = public_url_key(url)
          [id, url] if key && !urls.include?(key) && !uris.include?(rdf_uri)
        end
      end
    end

    def result(status, lists: [], retired: [], valid_until: nil)
      Result.new(status: status, retired: retired, valid_until: valid_until,
        lists: lists.map { |list| list.except(:url_keys, :rdf_uris, :valid_until) })
    end

    def inventory_for(page, selected, class_names)
      metadata = { webpage_id: page.id, url: page.url, status: "unverified" }
      by_label = selected.group_by { |statement| statement.source.property.label }
      target = only_statement(by_label, AddWebpagesJob::RDF_CLASS_LABEL)
      return metadata.merge(reason: "invalid_discovery_class") unless current_statement?(target)
      target_class = target.cache.to_s.strip
      if target_class != "Event"
        # A fixed data-only/non-event list has no say in event inventory.
        if target.manual? && (target_class == AddWebpagesJob::DATA_ONLY_CLASS || class_names.include?(target_class))
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
      unless timestamps.all? { |stamp| stamp && stamp <= @as_of } &&
          timestamps.max - timestamps.min <= MAX_LIST_REFRESH_SKEW
        return metadata.merge(reason: "stale_or_unpaired_list")
      end

      refreshed_at = timestamps.min
      metadata = metadata.merge(refreshed_at: refreshed_at.iso8601, count: url_keys.size)
      if changed_at && refreshed_at < changed_at
        return metadata.merge(reason: "list_configuration_changed")
      end
      if refreshed_at < @as_of - MAX_LIST_AGE
        return metadata.merge(reason: "stale_list")
      end

      metadata.merge(status: "event", url_keys: url_keys, rdf_uris: rdf_uris, valid_until: refreshed_at + MAX_LIST_AGE)
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
