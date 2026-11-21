module Statements
  class RefreshWebpageStatementsService
    def self.sources_for_webpage(webpage, default_language: "en", property_ids: nil)
      languages = [webpage.language]
      languages << "" if webpage.language == default_language

      scoped_property_ids = property_ids_for_class_name(webpage.rdfs_class.name, [])
      if property_ids.present?
        allowed_ids = Array(property_ids).map(&:to_i)
        scoped_property_ids.select! { |property_id| allowed_ids.include?(property_id.to_i) }
      end

      scoped_property_ids.flat_map do |property_id|
        Source.where(website_id: webpage.website_id, language: languages, property_id: property_id)
      end
    end

    def self.property_ids_for_class_name(rdfs_class_name, property_ids)
      class_list = rdfs_class_name.to_s.split(",")
      class_list.each do |class_name|
        rdfs_class = RdfsClass.where(name: class_name).first
        next unless rdfs_class

        rdfs_class.properties.each do |property|
          property_ids << property.id
          if property.value_datatype == "bnode" && property.expected_class != rdfs_class_name
            property_ids_for_class_name(property.expected_class, property_ids)
          end
        end
      end
      property_ids
    end

    def initialize(refresh_helper: ApplicationController.helpers)
      @refresh_helper = refresh_helper
    end

    def call(webpage:, default_language: "en", scrape_options: {})
      error_list = []
      refresh_options = normalized_scrape_options(scrape_options)

      self.class.sources_for_webpage(webpage, default_language: default_language).each do |src|
        stat = Statement.find_or_initialize_by(webpage_id: webpage.id, source_id: src.id)
        if stat.new_record?
          source_is_manual = src.algorithm_value.start_with?("manual=")
          stat.manual = source_is_manual
          stat.selected_individual = src.selected
          stat.status = "initial"
          stat.status_origin = "condenser_create"
        end

        next if stat.manual && %w[ok updated].include?(stat.status)

        @refresh_helper.refresh_statement_helper(stat, refresh_options.dup)
        stat.update(status: "updated") if src.auto_review && stat.status == "initial"
        error_list << { "Property id #{src.property_id}" => stat.errors.messages } if stat.errors.any?
      end

      error_list
    end

    private

    def normalized_scrape_options(scrape_options)
      return {} unless scrape_options.respond_to?(:to_h)

      scrape_options.to_h.symbolize_keys
    end
  end
end
