module Distillator
  # Serialize paired transition fetches for the same source host across workers.
  # PostgreSQL releases the slot if a worker loses its database session.
  class TransitionFetchSlot
    POLL_SECONDS = 0.25

    def self.call(uri:, wait_allowed: nil)
      host = source_host(uri)
      return yield(0) if host.blank?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.with_connection do |connection|
        key = "hashtextextended(#{connection.quote("distillator.transition_fetch:#{host}")}, 0)"
        loop do
          break if wait_allowed && !wait_allowed.call

          acquired = ActiveRecord::Base.uncached { connection.select_value("SELECT pg_try_advisory_lock(#{key})") }
          if acquired
            begin
              wait_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
              break yield(wait_ms)
            ensure
              ActiveRecord::Base.uncached { connection.select_value("SELECT pg_advisory_unlock(#{key})") }
            end
          end
          break unless wait_allowed

          sleep(POLL_SECONDS)
        end
      end
    end

    def self.source_host(uri)
      Addressable::URI.parse(WringerUrlKey.call(uri).normalized_url).normalized_host&.delete_suffix(".")&.delete_prefix("www.")
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
      nil
    end
    private_class_method :source_host
  end
end
