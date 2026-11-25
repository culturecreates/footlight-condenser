module Events
  class ResourcePublishability
    LOCATION_LABELS = %w[Location VirtualLocation].freeze
    REQUIRED_LABELS = (Webpage::PUBLISHABLE_REQUIRED_PROPERTY_LABELS | LOCATION_LABELS).freeze
    REQUIREMENTS = { "Title" => ["Title"], "Dates" => ["Dates"], "Location" => LOCATION_LABELS }.freeze
    SOURCE_LANGUAGE_SQL = "LOWER(COALESCE(sources.language, ''))".freeze

    def initialize(pages)
      @pages = pages.reorder(nil)
    end

    def publishable_resources
      Webpage.unscoped.from(usable_field_groups(selected_fields), :event_fields)
        .group("event_fields.website_id", "event_fields.rdf_uri")
        .having("BOOL_OR(event_fields.label = ?) AND BOOL_OR(event_fields.label = ?) AND BOOL_OR(event_fields.label IN (?))",
          "Title", "Dates", LOCATION_LABELS)
        .select("event_fields.website_id", "event_fields.rdf_uri")
    end

    def title_counts_by_language
      titles = usable_field_groups(selected_fields.where(properties: { label: "Title" }))
      Webpage.unscoped.from(titles, :event_fields).group("event_fields.website_id", "event_fields.source_language").count
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

    def missing_requirements
      usable_value = Arel.sql(Statement.sanitize_sql_array([usable_value_sql, Webpage::PUBLISHABLE_STATUSES]))
      groups = selected_fields.pluck("webpages.rdf_uri", "properties.label", Arel.sql(SOURCE_LANGUAGE_SQL),
        :status, usable_value).group_by(&:first)

      @pages.distinct.pluck(:rdf_uri).sort_by(&:to_s).to_h do |uri|
        fields = groups.fetch(uri, []).group_by { |_, label, _language, _status, _usable| label }
        missing = REQUIREMENTS.filter_map do |field, labels|
          matches = labels.flat_map { |label| fields.fetch(label, []) }
          selections = matches.group_by { |_, label, language, _status, _usable| [label, language] }
          next if selections.values.any? { |entries| entries.one? && entries.first.last }

          reasons = selections.map do |(label, language), entries|
            if entries.many?
              field_language = " (#{language.upcase})" if language.present?
              "Multiple selected #{label} statements#{field_language}"
            else
              status = entries.first[3]
              case status
              when "initial" then "#{label} needs review"
              when "missing" then "#{label} extraction is missing"
              when *Webpage::PUBLISHABLE_STATUSES then "#{label} value is empty or unusable"
              else "#{label} status is #{status.presence || 'unset'}"
              end
            end
          end
          { field: field, reasons: reasons.uniq.presence || ["No selected #{labels.join(' or ')} statement"] }
        end
        [uri, missing]
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

    def usable_field_groups(fields)
      fields.group("webpages.website_id", "webpages.rdf_uri", "properties.label", Arel.sql(SOURCE_LANGUAGE_SQL))
        .having("COUNT(*) = 1 AND BOOL_AND(#{usable_value_sql})", Webpage::PUBLISHABLE_STATUSES)
        .select("webpages.website_id", "webpages.rdf_uri", "properties.label", Arel.sql("#{SOURCE_LANGUAGE_SQL} AS source_language"))
    end

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
