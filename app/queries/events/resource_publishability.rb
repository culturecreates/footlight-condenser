module Events
  class ResourcePublishability
    LOCATION_LABELS = %w[Location VirtualLocation].freeze
    REQUIRED_LABELS = (Webpage::PUBLISHABLE_REQUIRED_PROPERTY_LABELS | LOCATION_LABELS).freeze

    def initialize(pages)
      @pages = pages.reorder(nil)
    end

    def publishable_resources
      fields = selected_fields
        .group("webpages.website_id", "webpages.rdf_uri", "properties.label", Arel.sql("LOWER(COALESCE(sources.language, ''))"))
        .having("COUNT(*) = 1 AND BOOL_AND(#{usable_value_sql})", Webpage::PUBLISHABLE_STATUSES)
        .select("webpages.website_id", "webpages.rdf_uri", "properties.label")

      Webpage.unscoped.from(fields, :event_fields)
        .group("event_fields.website_id", "event_fields.rdf_uri")
        .having("BOOL_OR(event_fields.label = ?) AND BOOL_OR(event_fields.label = ?) AND BOOL_OR(event_fields.label IN (?))",
          "Title", "Dates", LOCATION_LABELS)
        .select("event_fields.website_id", "event_fields.rdf_uri")
    end

    def publishable_pages
      @pages.where("(webpages.website_id, webpages.rdf_uri) IN (#{publishable_resources.to_sql})")
    end

    # A required value may be verified on a sibling only when that sibling is
    # part of this check. Preserve the requirement on any page that supplies it.
    def self.required_fields_by_page(webpages)
      groups = webpages.select { |page| page.rdfs_class.name == "Event" }.group_by { |page| [page.website_id, page.rdf_uri] }
      return {} if groups.empty?

      fields = new(Webpage.event_pages.where(id: groups.values.flatten.map(&:id))).usable_fields_by_page
      groups.each_value.with_object({}) do |group, requirements|
        supplied = group.flat_map { |page| fields.fetch(page.id, {}).keys }.uniq
        supplied << "Location" if supplied.include?("VirtualLocation")
        missing = (Webpage.publishable_required_property_labels - supplied).index_with { [] }

        group.each do |page|
          requirements[page.id] = fields.fetch(page.id, {}).merge(missing)
        end
      end
    end

    def usable_fields_by_page
      selected_fields.where(usable_value_sql, Webpage::PUBLISHABLE_STATUSES).order("webpages.id", "properties.label", "sources.id")
        .pluck("webpages.id", "properties.label", "sources.id")
        .group_by(&:first).transform_values do |rows|
          rows.group_by(&:second).transform_values { |matches| matches.map(&:last) }
        end
    end

    private

    def selected_fields
      Statement.joins(:webpage, source: :property)
        .where(selected_individual: true, webpage_id: @pages.reselect(:id))
        .where(properties: { label: REQUIRED_LABELS, rdfs_class_id: RdfsClass.where(name: "Event").select(:id) })
        .where("sources.website_id = webpages.website_id AND webpages.rdf_uri IS NOT NULL AND webpages.rdf_uri <> ''")
    end

    def usable_value_sql
      <<~SQL.squish
        statements.status IN (?)
        AND BTRIM(COALESCE(statements.cache, '')) NOT IN ('', '[]', 'null', '""')
        AND (properties.label <> 'Dates' OR LENGTH(BTRIM(statements.cache)) > 3)
      SQL
    end
  end
end
