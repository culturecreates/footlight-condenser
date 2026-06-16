class ExportArtsdataService
  PUBLISHABLE_STATES = %w[ok updated].freeze

  def self.call(seedurl:)
    new(seedurl).call
  end

  def self.production_equivalent(seedurl:)
    new(seedurl).production_equivalent
  end

  def initialize(seedurl)
    @seedurl = seedurl
  end

  def call
    grouped_started_at = Time.current if timing_enabled?
    grouped_events = website_statements_by_event
    if grouped_started_at
      puts "Grouping: #{(Time.current - grouped_started_at).round(3)}s"
    end

    publishable_events = publishable_events_for(grouped_events)

    dump_started_at = Time.current if timing_enabled?
    dump = JsonldGenerator.dump_events(publishable_events)
    if dump_started_at
      puts "Dump: #{(Time.current - dump_started_at).round(3)}s"
    end

    dump
  end

  def production_equivalent
    JsonldGenerator.dump_events_old(production_equivalent_publishable_events)
  end

  private

  def website_statements_by_event
    events_by_uri = Hash.new { |hash, key| hash[key] = {} }

    statements.each do |statement|
      property_label = make_key(statement.source.property.label, statement.source.language)
      event_uri = statement.webpage.rdf_uri

      if events_by_uri[event_uri][property_label].present?
        events_by_uri[event_uri][property_label] = {
          cache: statement.cache,
          status: "problem",
          selected_individual: statement.selected_individual
        }
      else
        events_by_uri[event_uri][property_label] = {
          cache: statement.cache,
          status: statement.status,
          selected_individual: statement.selected_individual
        }
        events_by_uri[event_uri][:archive_date] ||= { cache: statement.webpage.archive_date }
      end
    end

    events_by_uri
  end

  def statements
    return Statement.none if event_class_id.nil?

    @statements ||=
      Statement
      .joins(:webpage, source: :website)
      .includes({ source: [:property, :website] }, :webpage)
      .where(
        websites: { seedurl: @seedurl },
        webpages: {
          archive_date: [(Time.zone.now - 3000.years)..(Time.zone.now + 3000.years)],
          rdfs_class_id: event_class_id
        }
      )
      .where(selected_individual: true)
  end

  def event_class_id
    @event_class_id ||= RdfsClass.find_by(name: "Event")&.id
  end

  def make_key(property, language)
    key = property.sub(" ", "_").downcase
    key += "_#{language.downcase}" if language.present?
    key
  rescue StandardError
    "failed to make key"
  end

  def event_publishable?(data)
    return false unless PUBLISHABLE_STATES.include?(data.dig("dates", :status))
    return false unless PUBLISHABLE_STATES.include?(data.dig("location", :status)) ||
                        PUBLISHABLE_STATES.include?(data.dig("virtuallocation", :status))
    return false unless PUBLISHABLE_STATES.include?(data.dig("title_en", :status)) ||
                        PUBLISHABLE_STATES.include?(data.dig("title_fr", :status)) ||
                        PUBLISHABLE_STATES.include?(data.dig("title", :status))

    true
  end

  def timing_enabled?
    ENV["EXPORT_ARTSDATA_TIMING"].present?
  end

  def production_equivalent_publishable_events
    publishable_events_for(website_statements_by_event)
  end

  def publishable_events_for(grouped_events)
    grouped_events.filter_map do |rdf_uri, event_data|
      rdf_uri if event_publishable?(event_data)
    end
  end
end
