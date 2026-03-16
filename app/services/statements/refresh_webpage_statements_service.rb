module Statements
  class RefreshWebpageStatementsService
    def initialize(refresh_helper: ApplicationController.helpers)
      @refresh_helper = refresh_helper
    end

    def call(webpage:, default_language: "en", scrape_options: {})
      error_list = []
      languages = [webpage.language]
      languages << "" if webpage.language == default_language

      property_ids = extract_property_ids(webpage.rdfs_class.name, [])
      property_ids.each do |property_id|
        sources = Source.where(website_id: webpage.website, language: languages, property_id: property_id)
        sources.each do |src|
          statements = Statement.where(webpage_id: webpage.id, source_id: src.id)
          stat = if statements.blank?
                   source_is_manual = src.algorithm_value.start_with?("manual=")
                   statements.new(
                     manual: source_is_manual,
                     selected_individual: src.selected,
                     status: "initial",
                     status_origin: "condenser_create"
                   )
                 else
                   statements.first
                 end

          next if stat.manual && %w[ok updated].include?(stat.status)

          @refresh_helper.refresh_statement_helper(stat, scrape_options)
          stat.update(status: "updated") if src.auto_review && stat.status == "initial"
          error_list << { "Property id #{property_id}" => stat.errors.messages } if stat.errors.any?
        end
      end

      error_list
    end

    private

    def extract_property_ids(rdfs_class_name, property_ids)
      class_list = rdfs_class_name.split(",")
      class_list.each do |c|
        rdfs_class = RdfsClass.where(name: c).first
        next unless rdfs_class

        rdfs_class.properties.each do |property|
          property_ids << property.id
          if property.value_datatype == "bnode" && property.expected_class != rdfs_class_name
            extract_property_ids(property.expected_class, property_ids)
          end
        end
      end
      property_ids
    end
  end
end
