module Distillator
  class TransitionEventSample
    LOOKBACK_RUNS = 50

    def self.select(run:, scope:, size:, scope_at:)
      sample = run.event_sample || create_sample(run, scope, size, scope_at)
      picked = sample.fetch("pages")
      pages_by_id = scope.where(id: picked.pluck("id")).index_by(&:id)
      picked.map do |entry|
        page = pages_by_id[entry.fetch("id")]
        unless page&.url == entry.fetch("url")
          raise TransitionRun::ConfigurationChanged, "The saved Light sample changed. Run a new workflow."
        end
        page
      end
    end

    def self.create_sample(run, scope, size, scope_at)
      seed = SecureRandom.random_number(2**63)
      random = Random.new(seed)
      recency = recent_light_page_ids(run)
      picked = scope.reorder(:id).pluck(:id, :url).map do |id, url|
        [{ "id" => id, "url" => url }, recency.fetch(id, 0), random.rand]
      end.min_by(size) { |_, seen, random_order| [seen, random_order] }.map(&:first)
      { "seed" => seed.to_s, "scope_at" => scope_at.iso8601(6), "pages" => picked }.tap do |sample|
        run.save_event_sample!(sample)
      end
    end

    def self.recent_light_page_ids(run)
      light_runs = run.website.transition_runs.current_checks.completed
        .where(check_options: TransitionBatch::CHECK_PROFILES.fetch("light"))
        .order(id: :desc).limit(LOOKBACK_RUNS).select(:id)
      TransitionEvidence.where(transition_run_id: light_runs, check_kind: "fetch_parity")
        .joins(<<~SQL.squish)
          CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(details -> 'representative_url_results') = 'array'
              THEN details -> 'representative_url_results' ELSE '[]'::jsonb END
          ) AS attempted_page
        SQL
        .where("attempted_page ->> 'attempted_condenser_fetch' = 'true' AND attempted_page ->> 'webpage_id' IS NOT NULL")
        .group(Arel.sql("(attempted_page ->> 'webpage_id')::bigint")).maximum(:transition_run_id)
    end
    private_class_method :create_sample, :recent_light_page_ids
  end
end
