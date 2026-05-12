namespace :distillator do
  namespace :cache do
    desc "Backfill materialized cache health fields"
    task backfill_health: :environment do
      total = Distillator::FetchCache.count
      processed = 0

      Distillator::FetchCache.find_each(batch_size: 1000) do |cache|
        attrs = Distillator::CacheHealthMaterializer.attributes_for(cache)
        cache.update_columns(attrs.merge(updated_at: Time.current))
        processed += 1

        next unless (processed % 1000).zero? || processed == total

        Rails.logger.info(
          event: "distillator.cache.backfill_health",
          processed: processed,
          total: total
        )
      end
    end
  end
end
