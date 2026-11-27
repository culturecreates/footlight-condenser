module ResourceLists
  class DiscoveryClass
    LABEL = "RDF Class".freeze
    DATA_ONLY = "None".freeze
    Result = Struct.new(:class_name, :extracted_statement, :warning, :reason, keyword_init: true)

    def self.resolve(statements, website_id:, class_names:)
      return Result.new(reason: "missing_discovery_class") if statements.empty?

      selected = statements.select { |row| row.selected_individual? && row.source.selected? }
      return Result.new(reason: "unselected_discovery_class") if selected.empty?
      unless selected.all? { |row| row.source.website_id == website_id }
        return Result.new(reason: "wrong_discovery_class_website")
      end

      names = selected.map { |row| row.cache.to_s.strip }.uniq
      return Result.new(reason: "conflicting_discovery_classes") if names.size > 1

      name = names.first
      return Result.new(reason: "missing_discovery_class_value") if name.blank?
      return Result.new(reason: "unknown_discovery_class") unless name == DATA_ONLY || class_names.include?(name)

      fixed, extracted = selected.partition { |row| row.source.algorithm_value.to_s.strip.start_with?("manual=") }
      unless fixed.all? { |row| row.source.algorithm_value.to_s.strip.delete_prefix("manual=").strip == name }
        return Result.new(reason: "mismatched_manual_discovery_class")
      end
      unless fixed.all? { |row| row.is_initial? || Webpage::PUBLISHABLE_STATUSES.include?(row.status) }
        return Result.new(reason: "invalid_manual_discovery_class_status")
      end

      if extracted.any?
        return Result.new(reason: "ambiguous_discovery_class") unless selected.one?

        row = extracted.first
        return Result.new(reason: "manual_discovery_class_without_fixed_source") if row.manual?
        return Result.new(reason: "unreviewed_extracted_discovery_class") unless Webpage::PUBLISHABLE_STATUSES.include?(row.status)

        refreshed = row.cache_refreshed
        unless refreshed && [row.source.updated_at, row.source.property.updated_at].compact.all? { |changed| refreshed >= changed }
          return Result.new(reason: "stale_extracted_discovery_class")
        end
      end

      warning = "duplicate_discovery_class_declarations" if fixed.size > 1
      Result.new(class_name: name, extracted_statement: extracted.first, warning: warning)
    end
  end
end
