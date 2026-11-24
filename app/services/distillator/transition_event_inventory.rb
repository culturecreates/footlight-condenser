require "json"
require "time"

module Distillator
  # Compare the site's transition candidates with verified discovery lists.
  class TransitionEventInventory
    MAX_LIST_AGE = 48.hours
    MAX_LIST_REFRESH_SKEW = 10.minutes
    DISCOVERY_LABELS = [AddWebpagesJob::RDF_CLASS_LABEL, AddWebpagesJob::URI_LIST_LABEL, AddWebpagesJob::WEBPAGE_URL_LIST_LABEL].freeze
    Result = Struct.new(:status, :lists, :valid_until, :selected_event_urls_missing, :archived_publishable_count, keyword_init: true)

    def self.statement_scope(website_ids, class_name)
      Statement.joins(webpage: :rdfs_class, source: :property)
        .where(webpages: { website_id: website_ids }, rdfs_classes: { name: class_name })
        .where("sources.website_id = webpages.website_id")
        .where("statements.selected_individual = TRUE OR sources.selected = TRUE")
    end

    def self.discovery_scope(website_ids)
      statement_scope(website_ids, "ResourceList").where(properties: { label: DISCOVERY_LABELS })
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

      record_missing_event_counts(event_lists_by_site, events, results)
      results
    end

    private

    def record_missing_event_counts(event_lists_by_site, events, results)
      registered = Webpage.event_pages.where(website_id: event_lists_by_site.keys).pluck(:website_id, :url).group_by(&:first)
      candidates = events.where(website_id: event_lists_by_site.keys).pluck(:website_id, :url, :rdf_uri).group_by(&:first)
      event_lists_by_site.each do |website_id, lists|
        urls = lists.flat_map { |list| list[:url_keys] }.to_set
        imported = registered.fetch(website_id, []).filter_map { |_, url| public_url_key(url) }.to_set
        unless urls.subset?(imported)
          results.fetch(website_id).status = "discovery_pending_import"
          next
        end
        uris = lists.flat_map { |list| list[:rdf_uris] }.to_set
        results.fetch(website_id).selected_event_urls_missing = candidates.fetch(website_id, []).count do |_, url, rdf_uri|
          key = public_url_key(url)
          key && !urls.include?(key) && !uris.include?(rdf_uri)
        end
      end
    end

    def result(status, lists: [], valid_until: nil)
      Result.new(status: status, valid_until: valid_until,
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
      metadata = metadata.merge(refreshed_at: refreshed_at.iso8601, refresh_completed_at: timestamps.max.iso8601(6), count: url_keys.size)
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

    def public_url_key(value)
      uri = Addressable::URI.parse(value.to_s).normalize
      return unless uri.scheme.in?(%w[http https]) && uri.host.present? && uri.userinfo.nil?

      [uri.host.delete_prefix("www."), uri.port, uri.path.delete_suffix("/"), uri.query]
    rescue Addressable::URI::InvalidURIError, ArgumentError
      nil
    end
  end
end
