module Distillator
  class WebsiteRenderedFetchSummary
    LABELS = { "ResourceList" => "RL", "Event" => "E" }.freeze

    def self.for_websites(website_ids)
      usage = website_ids.index_with { [] }
      return usage if usage.empty?

      events = Webpage.event_pages.public_source_urls.active.where(website_id: website_ids)
      lists = Webpage.joins(:rdfs_class).where(rdfs_classes: { name: "ResourceList" })
      lists = lists.where(website_id: website_ids).or(lists.where(discovery_target_website_id: website_ids))
      algorithms = {}

      { "ResourceList" => lists, "Event" => events }.each do |class_name, scope|
        # Only keep a URL in the grouping when it can use the iframe rendering convention.
        iframe_candidate = Arel.sql("CASE WHEN RTRIM(webpages.url) LIKE '%iframe' THEN webpages.url END")
        groups = scope.joins(:website).distinct.pluck("webpages.website_id", "webpages.discovery_target_website_id",
          "webpages.language", "websites.default_language", iframe_candidate)
        next if groups.empty?

        rendered_languages = rendered_source_languages(class_name, groups.map(&:first).uniq, algorithms)
        groups.each do |owner_id, target_id, language, default_language, url|
          next unless iframe_source?(url) || rendered_languages.include?([owner_id, language]) ||
            (language == default_language && rendered_languages.include?([owner_id, ""]))

          [owner_id, target_id].compact.uniq.each do |website_id|
            usage[website_id] |= [class_name] if usage.key?(website_id)
          end
        end
      end

      usage
    end

    def self.rendered_source_languages(class_name, website_ids, algorithms)
      properties = Statements::RefreshWebpageStatementsService.property_ids_for_class_name(class_name, [])
      sources = Source.where(website_id: website_ids, property_id: properties)
        .where("render_js = TRUE OR algorithm_value LIKE ? OR algorithm_value LIKE ?", "%renderjs_url=%", "%$$%")
        .pluck(:website_id, :language, :render_js, :algorithm_value)
      # Library expansion reads shared definitions and never runs the DSL.
      DslLibraryEntry.cache do
        sources.each_with_object(Set.new) do |(website_id, language, render_js, algorithm), languages|
          uses_renderer = render_js || algorithms.fetch(algorithm) { algorithms[algorithm] = renders_url?(algorithm) }
          languages << [website_id, language] if uses_renderer
        end
      end
    end

    def self.renders_url?(algorithm)
      Dsl::LibraryExpander.call(algorithm.to_s).fetch(:steps).any? { |step| step.start_with?("renderjs_url=") }
    rescue Dsl::LibraryExpander::Error
      false
    end

    def self.iframe_source?(url)
      url && WringerUrlKey.call(url, include_fragment: true).uri_key.end_with?("iframe")
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
      false
    end

    private_class_method :rendered_source_languages, :renders_url?, :iframe_source?
  end
end
