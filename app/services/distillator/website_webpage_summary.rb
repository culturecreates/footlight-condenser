module Distillator
  class WebsiteWebpageSummary
    CLASS_BUCKETS = %w[Event Person Place ResourceList WebPage].freeze

    def self.for_websites(website_ids)
      ids = Array(website_ids).map(&:to_i).uniq
      return {} if ids.empty?

      summaries = ids.index_with { empty_summary }

      populate_totals!(summaries, ids)
      populate_class_counts!(summaries, ids)
      populate_publishable_counts!(summaries, ids)
      populate_event_resources!(summaries, ids)

      summaries
    end

    def self.empty_summary
      {
        total: 0,
        public_urls: 0,
        internal_uris: 0,
        by_class: CLASS_BUCKETS.index_with { 0 }.merge("Other" => 0),
        publishable: 0,
        not_publishable: 0,
        publishable_event_page_percentage: nil,
        event_resources: 0,
        publishable_event_resources: 0,
        publishable_event_resource_percentage: nil,
        event_languages: [],
        fully_localized_event_resources: nil
      }
    end

    def self.populate_totals!(summaries, website_ids)
      counts = Webpage.where(website_id: website_ids)
                      .group(:website_id)
                      .pluck(
                        :website_id,
                        Arel.sql("COUNT(*)"),
                        Arel.sql("SUM(CASE WHEN #{Webpage.public_source_url_sql} THEN 1 ELSE 0 END)"),
                        Arel.sql("SUM(CASE WHEN #{Webpage.public_source_url_sql} THEN 0 ELSE 1 END)")
                      )

      counts.each do |website_id, total, public_urls, internal_uris|
        summary = summaries.fetch(website_id)
        summary[:total] = total.to_i
        summary[:public_urls] = public_urls.to_i
        summary[:internal_uris] = internal_uris.to_i
      end
    end

    def self.populate_class_counts!(summaries, website_ids)
      Webpage.left_outer_joins(:rdfs_class)
             .where(website_id: website_ids)
             .group(:website_id, "rdfs_classes.name")
             .count
             .each do |(website_id, class_name), count|
        bucket = CLASS_BUCKETS.include?(class_name) ? class_name : "Other"
        summaries.fetch(website_id)[:by_class][bucket] += count.to_i
      end
    end

    def self.populate_publishable_counts!(summaries, website_ids)
      Webpage.where(website_id: website_ids)
             .publishable
             .group(:website_id)
             .count
             .each do |website_id, count|
        summaries.fetch(website_id)[:publishable] = count.to_i
      end

      summaries.each_value do |summary|
        summary[:not_publishable] = summary[:total] - summary[:publishable]
        event_count = summary[:by_class].fetch("Event")
        summary[:publishable_event_page_percentage] = summary[:publishable] * 100.0 / event_count if event_count.positive?
      end
    end

    def self.populate_event_resources!(summaries, website_ids)
      scope = Webpage.event_pages.where(website_id: website_ids)
      events = Events::ResourcePublishability.new(scope)
      published_by_site = Webpage.from(events.publishable_resources, :event_resources).group("event_resources.website_id").count
      # One row per language and resource. A translated page counts once, even
      # when several URLs share the same language.
      languages_by_site = scope.where.not(rdf_uri: [nil, ""]).distinct
        .pluck(:website_id, :rdf_uri, Arel.sql("LOWER(BTRIM(webpages.language))")).group_by(&:first)
      summaries.each do |website_id, summary|
        resources = languages_by_site.fetch(website_id, []).group_by { |_, uri, _| uri }
        next if resources.empty?

        languages = resources.values.map { |rows| rows.map(&:last).compact_blank }
        expected = languages.flatten.uniq.sort
        published = published_by_site.fetch(website_id, 0)
        summary[:event_resources] = resources.size
        summary[:publishable_event_resources] = published
        summary[:publishable_event_resource_percentage] = published * 100.0 / resources.size
        summary[:event_languages] = expected
        if expected.size > 1
          summary[:fully_localized_event_resources] = languages.count { |locales| locales.size == expected.size }
        end
      end
    end

    private_class_method :populate_totals!, :populate_class_counts!, :populate_publishable_counts!, :populate_event_resources!
  end
end
