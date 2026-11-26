require "digest"
require "json"
require "time"

module Distillator
  # Compare the site's transition candidates with verified discovery lists.
  class TransitionEventInventory
    MAX_LIST_AGE = 48.hours
    MAX_LIST_REFRESH_SKEW = 10.minutes
    DISCOVERY_LABELS = [AddWebpagesJob::RDF_CLASS_LABEL, AddWebpagesJob::URI_LIST_LABEL, AddWebpagesJob::WEBPAGE_URL_LIST_LABEL].freeze
    Result = Struct.new(:status, :lists, :valid_until, :selected_event_urls_missing, :archived_publishable_count,
      :pending_import, :unpublishable_urls_count, :unpublishable_listed_pages, keyword_init: true)

    def self.discovery_scope(list_ids)
      Statement.joins(:webpage, source: :property)
        .where(webpage_id: list_ids, properties: { label: DISCOVERY_LABELS })
        .where(<<~SQL.squish, AddWebpagesJob::RDF_CLASS_LABEL)
          properties.label = ? OR (sources.website_id = webpages.website_id AND
            (statements.selected_individual = TRUE OR sources.selected = TRUE))
        SQL
    end

    def self.list_pages(website_ids)
      lists = Webpage.joins(:rdfs_class).where(rdfs_classes: { name: "ResourceList" })
      lists.where(discovery_target_website_id: website_ids)
        .or(lists.where(discovery_target_website_id: nil, website_id: website_ids))
    end

    def self.definition_digest(website_id)
      lists = list_pages(website_id).order(:id).pluck(:id, :url, :language, :rdf_uri, :website_id, :discovery_target_website_id)
      owner_ids = lists.map { |row| row[4] }
      owners = Website.where(id: owner_ids).order(:id).pluck(:id, :seedurl, :default_language)
      sources = Source.joins(property: :rdfs_class)
        .where(website_id: owner_ids, rdfs_classes: { name: "ResourceList" })
        .order(:id).pluck(*Source.column_names.map { |column| Source.arel_table[column] })
      properties = Property.where(id: sources.map { |row| row[Source.column_names.index("property_id")] })
        .order(:id).pluck(*Property.column_names)
      Digest::SHA256.hexdigest(JSON.generate([lists, owners, sources, properties]))
    end

    def self.list_digest(urls, rdf_uris)
      Digest::SHA256.hexdigest(JSON.generate(urls.zip(rdf_uris).uniq.sort_by(&:to_json)))
    end

    def initialize(as_of:)
      @as_of = as_of
    end

    def for_websites(website_ids, events:, diagnostics: false)
      pages = self.class.list_pages(website_ids).order(:id).group_by { |page| page.discovery_target_website_id || page.website_id }
      results = website_ids.index_with { result("no_discovery_lists") }
      return results if pages.empty?

      selected = self.class.discovery_scope(pages.values.flatten.map(&:id)).includes(source: :property).group_by(&:webpage_id)
      class_names = RdfsClass.pluck(:name).to_set
      inventories = {}
      pages.each do |website_id, lists|
        evidence = lists.map { |page| inventory_for(page, selected.fetch(page.id, []), class_names) }
        ResourceLists::Pagination.review!(lists, evidence)
        inventories[website_id] = evidence.select { |list| list.key?(:url_keys) }
        event_lists = evidence.select { |list| list[:status] == "event" }
        status = if evidence.any? { |list| list[:status] == "unverified" }
          "discovery_unverified"
        elsif event_lists.empty? || event_lists.all? { |list| list[:count].zero? }
          # A fully empty calendar may be legitimate, but cannot prove live discovery.
          "no_event_discovery"
        else
          "confirmed_discovery"
        end
        results[website_id] = result(status, lists: evidence, valid_until: event_lists.map { |list| list[:valid_until] }.min)
      end
      inventories.reject! { |_, lists| lists.empty? }
      record_missing_event_counts(inventories, events, results, diagnostics: diagnostics) if inventories.any?
      results
    end

    def snapshot_for(page)
      statements = self.class.discovery_scope([page.id]).includes(source: :property)
      inventory_for(page, statements, RdfsClass.pluck(:name).to_set)
    end

    private

    def record_missing_event_counts(inventories, events, results, diagnostics:)
      registered = Webpage.event_pages.where(website_id: inventories.keys)
      existing_records = Webpage.where(website_id: inventories.keys).pluck(:website_id, :url).group_by(&:first) if diagnostics
      urls_by_site = registered.pluck(:website_id, :url).group_by(&:first)
      active_pages = registered.active(@as_of).without_reviewed_transition_exclusions.public_source_urls
        .pluck(:website_id, :id, :url, :rdf_uri).group_by(&:first)
      candidates = events.where(website_id: inventories.keys)
        .pluck(:website_id, :id, :url, :rdf_uri).group_by(&:first)
      inventories.each do |website_id, lists|
        inventory = results.fetch(website_id)
        urls = lists.flat_map { |list| list[:url_keys] }.to_set
        imported = urls_by_site.fetch(website_id, []).filter_map { |_, url| public_url_key(url) }.to_set
        inventory.pending_import = !urls.subset?(imported)
        if diagnostics
          exact_urls = existing_records.fetch(website_id, []).map(&:last).to_set
          by_page = lists.index_by { |list| list[:webpage_id] }
          inventory.lists.each do |list|
            source = by_page[list[:webpage_id]]
            next unless source

            discovered = source[:urls].uniq
            list[:discovered_count] = discovered.size
            list[:known_count] = discovered.count { |url| exact_urls.include?(url) }
            list[:new_count] = discovered.size - list[:known_count]
            list[:missing_count] = source[:url_keys].uniq.count { |key| !imported.include?(key) }
          end
        end
        rows = candidates.fetch(website_id, [])
        eligible_ids = rows.map { |_, id, _, _| id }.to_set
        inventory.unpublishable_listed_pages = active_pages.fetch(website_id, []).filter_map do |_, id, url, uri|
          { webpage_id: id, url: url, rdf_uri: uri } if !eligible_ids.include?(id) && urls.include?(public_url_key(url))
        end
        inventory.unpublishable_urls_count = inventory.unpublishable_listed_pages.size

        next unless inventory.status == "confirmed_discovery"
        if inventory.pending_import
          inventory.status = "discovery_pending_import"
          next
        end
        uris = lists.flat_map { |list| list[:rdf_uris] }.to_set
        inventory.selected_event_urls_missing = rows.count do |_, _, url, rdf_uri|
          key = public_url_key(url)
          key && !urls.include?(key) && !uris.include?(rdf_uri)
        end
      end
    end

    def result(status, lists: [], valid_until: nil)
      Result.new(status: status, valid_until: valid_until,
        lists: lists.map { |list| list.except(:urls, :url_keys, :rdf_uris, :valid_until) })
    end

    def inventory_for(page, selected, class_names)
      metadata = { webpage_id: page.id, website_id: page.website_id, url: page.url, status: "unverified" }
      by_label = selected.group_by { |statement| statement.source.property.label }
      discovery = ResourceLists::DiscoveryClass.resolve(by_label.fetch(AddWebpagesJob::RDF_CLASS_LABEL, []),
        website_id: page.website_id, class_names: class_names)
      return metadata.merge(reason: discovery.reason) if discovery.reason

      metadata[:warning] = discovery.warning if discovery.warning
      return metadata.merge(status: "other_class") unless discovery.class_name == "Event"

      url_list = only_statement(by_label, AddWebpagesJob::WEBPAGE_URL_LIST_LABEL)
      uri_list = only_statement(by_label, AddWebpagesJob::URI_LIST_LABEL)
      payloads = [url_list, uri_list]
      if payloads.any?(&:nil?)
        missing = [AddWebpagesJob::WEBPAGE_URL_LIST_LABEL, AddWebpagesJob::URI_LIST_LABEL].any? { |label| by_label[label].blank? }
        return metadata.merge(reason: "ambiguous_list", extraction_reason: ("missing_statement_extraction" if missing))
      end
      return metadata.merge(reason: "manual_discovery_list_override") if payloads.any?(&:manual?)
      if payloads.any? { |statement| statement.source.algorithm_value.to_s.strip.start_with?("manual=") }
        return metadata.merge(reason: "fixed_discovery_list_payload")
      end
      return metadata.merge(reason: "unreviewed_discovery_list") if payloads.any?(&:is_initial?)
      unless payloads.all? { |statement| current_statement?(statement) }
        explanation = if payloads.any? { |statement| statement.is_problem? || statement.fetch_provenance.dig("attempt", "result") == "failed" }
          "extraction_failed"
        elsif payloads.any? { |statement| statement.cache_refreshed.nil? }
          "missing_statement_extraction"
        elsif payloads.all? { |statement| statement.cache_refreshed && statement.cache.present? } &&
            payloads.any? { |statement| [statement.source.updated_at, statement.source.property.updated_at].compact.any? { |changed| statement.cache_refreshed < changed } }
          "extraction_configuration_changed"
        end
        return metadata.merge(reason: "ambiguous_list", extraction_reason: explanation)
      end

      urls = string_array(url_list.cache)
      url_keys = urls&.map { |url| public_url_key(url) }
      rdf_uris = string_array(uri_list.cache)
      # Two saved empty arrays are a valid extraction, not missing evidence.
      # Missing/malformed arrays remain nil and must not pass this check.
      unless url_keys && rdf_uris && url_keys.size == rdf_uris.size && url_keys.none?(&:nil?)
        return metadata.merge(reason: "invalid_list", count: urls&.size, invalid_count: url_keys&.count(&:nil?))
      end

      timestamps = [discovery.extracted_statement, url_list, uri_list].compact.map(&:cache_refreshed)
      changed_at = [page.created_at, page.updated_at].compact.max
      unless timestamps.all? { |stamp| stamp && stamp <= @as_of } &&
          timestamps.max - timestamps.min <= MAX_LIST_REFRESH_SKEW
        return metadata.merge(reason: "stale_or_unpaired_list")
      end

      refreshed_at = timestamps.min
      metadata = metadata.merge(refreshed_at: refreshed_at.iso8601(6), refresh_completed_at: timestamps.max.iso8601(6), count: url_keys.size, invalid_count: 0)
      if changed_at && refreshed_at < changed_at
        return metadata.merge(reason: "list_configuration_changed")
      end
      metadata = metadata.merge(urls: urls, url_keys: url_keys, rdf_uris: rdf_uris,
        contents_digest: self.class.list_digest(urls, rdf_uris))
      if refreshed_at < @as_of - MAX_LIST_AGE
        return metadata.merge(reason: "stale_list")
      end

      metadata.merge(status: "event", valid_until: refreshed_at + MAX_LIST_AGE)
    end

    def only_statement(by_label, label)
      rows = by_label.fetch(label, [])
      rows.first if rows.one?
    end

    def current_statement?(statement)
      return false unless statement && Webpage::PUBLISHABLE_STATUSES.include?(statement.status) && statement.cache.present?
      return false unless statement.selected_individual? && statement.source.selected?

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
