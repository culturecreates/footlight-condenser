module Preprocessing
  class Monitor
    KINDS = %w[preprocessing_failure stale_refresh stale_inputs].freeze

    def self.call
      PreprocessingPolicy.find_each do |policy|
        evaluate(policy)
      rescue StandardError => error
        Rails.logger.error("[Preprocessing] Freshness check failed policy=#{policy.id} #{error.class}")
      end
    end

    def self.evaluate(policy)
      MonitoringIssue.transaction(requires_new: true) { policy.with_lock { evaluate_policy(policy) } }
    rescue StandardError => error
      Rails.logger.error("[Preprocessing] Freshness check failed policy=#{policy.id} #{error.class}")
      nil
    end

    def self.evaluate_policy(policy)
      unless policy.enabled? && policy.monitoring_enabled?
        MonitoringIssue.open_issues.where(preprocessing_policy_id: policy.id, kind: KINDS).update_all(resolved_at: Time.current)
        return
      end
      target = policy.target
      identity_error = policy.identity_error(target)
      failure = identity_error || policy.last_error.presence
      # A DSL-opted-in issue already reports the same extraction failure.
      dsl_issue = target && MonitoringIssue.open_issues.where(fingerprint: MonitoringIssue.fingerprint_for(target)).exists?
      set_issue(policy, "preprocessing_failure", dsl_issue && !identity_error ? nil : failure, target)
      cutoff = Time.current - policy.stale_after_hours.hours
      stamp = target&.cache_refreshed
      stale = identity_error || stamp.nil? || stamp < cutoff || stamp > Time.current + 5.minutes
      set_issue(policy, "stale_refresh", stale ? "Required preprocessing statement ##{policy.statement_id} has no valid successful refresh within #{policy.stale_after_hours} hours. Last success: #{stamp || 'not recorded'}." : nil, target)
      stale_inputs = policy.input_observations.select do |item|
        time = item[:refreshed_at] && Time.iso8601(item[:refreshed_at])
        !item[:valid_identity] || time.nil? || time < cutoff || time > Time.current + 5.minutes
      end
      message = stale_inputs.map { |item| "##{item[:id]}: #{item[:valid_identity] ? (item[:refreshed_at] || 'never refreshed') : 'missing or moved to another website'}" }.join("; ")
      input_problem = stale_inputs.any? ? "Required inputs older than #{policy.stale_after_hours} hours or unavailable: #{message}" : nil
      saved_run = policy.runs.where(status: "succeeded").order(id: :desc).first
      if saved_run && stamp == saved_run.output_refreshed_at
        stale_observations = saved_run.input_observations.select do |item|
          time = item["refreshed_at"] && Time.iso8601(item["refreshed_at"])
          !item["valid_identity"] || time.nil? || time < saved_run.started_at - policy.stale_after_hours.hours || time > saved_run.started_at + 5.minutes
        end
        if stale_observations.any?
          ids = stale_observations.map { |item| "##{item['id']}" }.join(", ")
          input_problem = "Last saved policy result observed stale or unavailable inputs: #{ids}. Refresh those inputs, then rerun this policy. #{input_problem}".strip
        end
      end
      set_issue(policy, "stale_inputs", input_problem, target)
      policy.update_column(:last_checked_at, Time.current)
    end

    def self.set_issue(policy, kind, message, target)
      fingerprint = Digest::SHA256.hexdigest("preprocessing:#{policy.id}:#{kind}")
      if message.nil?
        MonitoringIssue.open_issues.where(fingerprint: fingerprint).update_all(resolved_at: Time.current)
        return
      end
      now = Time.current
      issue = MonitoringIssue.create_or_find_by!(fingerprint: fingerprint) do |record|
        record.assign_attributes(kind: kind, preprocessing_policy_id: policy.id, seedurl: policy.seedurl,
          source_id: policy.source_id, statement_id: policy.statement_id, message: message.first(1000), first_seen_at: now, last_seen_at: now, occurrences: 0)
      end
      issue.with_lock do
        changed = issue.resolved_at? || issue.message != message.first(1000)
        issue.update!(website_name: target&.webpage&.website&.name, url: target&.webpage&.url,
          property_name: target&.source&.property&.label, message: message.first(1000), resolved_at: nil,
          first_seen_at: issue.resolved_at? ? now : issue.first_seen_at, last_seen_at: now,
          occurrences: issue.occurrences + (changed || issue.occurrences.zero? ? 1 : 0))
      end
    end
    private_class_method :set_issue, :evaluate_policy
  end
end
