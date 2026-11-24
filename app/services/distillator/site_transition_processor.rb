module Distillator
  class SiteTransitionProcessor
    def initialize(runner: TransitionCheckRunner, rollout: RolloutTransition)
      @runner = runner
      @rollout = rollout
    end

    def perform(id, phase:)
      item = SiteTransition.find(id)
      token = claim(item, phase)
      return unless token
      # A durable delayed guard is queued before doing any verification work.
      # The pre-check guard also survives the handoff into Active/post-check.
      unless item.cancel_requested_at?
        guard = SiteTransitionWatchdogJob.set(wait_until: item.deadline_at).perform_later(item.id)
        raise "Could not schedule recovery guard" unless guard
      end
      run = item.current_run
      item.check_cancellation! unless run
      cancellation_check = item.method(:check_cancellation!)
      result = run.execute(resumable: run.options.sample_mode == "all", cancellation_check: cancellation_check) do
        @runner.call(website: item.website, transition_run: run, verify_active_path: item.phase == "postcheck",
          require_native_path: true, cancellation_check: cancellation_check)
      end
      if result == TransitionRun::CONTINUE
        item.check_cancellation!
        queue_continuation(item)
        return
      end
      return if run.reload.status.in?(%w[queued running]) # Another delivery owns the execution lock.

      finish_phase(item, token, run.reload)
    rescue TransitionRun::Cancelled => error
      recover(item, reason: error.message, token: token)
    rescue StandardError => error
      Rails.logger.warn(event: "distillator.site_transition.failed", id: id, error_class: error.class.name)
      recover(item, reason: error.message, token: token || item.reload.phase_token) if item && !item.reload.terminal?
    end

    def recover(item, reason:, token:)
      changed = owned(item, token) do |website|
        cancelled = item.cancel_requested_at?
        reason = TransitionRun::CANCELLED_MESSAGE if cancelled
        if (run = item.current_run)
          run.fail!(cancelled ? reason : "Workflow stopped: #{reason}")
          run.transition_checkpoints.delete_all if cancelled
          item.phase_results = item.phase_results.merge(item.phase => comparison_result(run, website).merge(reason: reason)) unless item.phase_results.key?(item.phase)
        end
        if website.distillator_mode == "active" && !item.batch.audit? && !item.phase_results["retained_active"]
          result = @rollout.call(website: website, to_mode: "shadow", actor: item.actor, reason: "Automatic recovery: #{reason}")
          unless result.success? && website.reload.distillator_mode == "shadow"
            finish(item, website, "recovery_failed", "Recovery failed: #{result.errors.join(', ')}. Original issue: #{reason}")
            next
          end
          item.phase_results = item.phase_results.merge("recovery" => { state: "completed", mode: "shadow", reason: reason })
        else
          item.phase_results = item.phase_results.merge("recovery" => { state: "not_needed", mode: website.distillator_mode })
        end
        finish(item, website, cancelled ? "cancelled" : "attention", reason)
      end
      item.batch.enqueue_next! if changed
    rescue StandardError => error
      # Do not claim recovery succeeded if persistence or the mode switch failed.
      item.reload
      if !item.terminal? && item.phase_token == token
        item.update!(status: "recovery_failed", phase: "finished", completed_at: Time.current,
          reason: "Recovery could not be confirmed (#{error.class.name}). Inspect the actual website mode.",
          final_mode: item.website&.reload&.distillator_mode, final_backend: nil)
        item.batch.enqueue_next!
      end
    end

    private

    def queue_continuation(item)
      SiteTransitionJob.perform_later(item.id, phase: item.phase)
    rescue StandardError => error
      Rails.logger.warn(event: "distillator.site_transition.continuation_enqueue_failed", id: item.id, error_class: error.class.name)
    end

    def claim(item, requested_phase)
      token = nil
      website = item.website
      unless website
        item.update!(status: "cancelled", phase: "finished", reason: "Website was deleted", completed_at: Time.current) unless item.terminal?
        item.batch.enqueue_next!
        return
      end
      website.with_lock do
        item.batch.with_lock do
          item.with_lock do
            next if item.terminal? || item.phase != requested_phase
            next if requested_phase == "queued" && item.batch.site_transitions.where(status: "running").where.not(id: item.id).exists?
            unless matches_operator_state?(item, website)
              finish_after_operator_change(item, website)
              next
            end
            if item.cancel_requested_at?
              token = item.phase_token
              next
            end
            if item.phase_started_at
              run = item.current_run
              token = item.phase_token if run && (run.status == "queued" || run.resumable?)
              next
            end
            can_discover = requested_phase == "queued" && item.batch.check_profile == "thorough" && !item.batch.audit? &&
              TransitionEventInventory.list_pages(website.id).exists?
            unless EventSiteSelection.eligible_ids([website]).include?(website.id) && (can_discover || website.webpages.event_pages.exists?)
              finish(item, website, "attention", "No eligible event pages are available, or this site is no longer an event site.")
              next
            end
            if requested_phase == "queued"
              unless can_discover || website.webpages.public_publishable_events.active.without_reviewed_transition_exclusions.exists?
                finish(item, website, "attention", "No active publishable event pages with public URLs are available.")
                next
              end

              if website.distillator_mode == "active" && !item.batch.audit? && migrated?(website)
                item.phase_results = item.phase_results.merge("retained_active" => true)
              end

              if website.distillator_mode == "legacy" ||
                  (item.batch.thorough_revalidation? && website.distillator_mode == "active" && !item.phase_results["retained_active"])
                result = @rollout.call(website: website, to_mode: "shadow", actor: item.actor, reason: "Start validation workflow ##{item.id}")
                raise result.errors.join(", ") unless result.success?
              end
              item.phase = website.distillator_mode == "active" ? "postcheck" : "precheck"
              item.expected_mode = website.distillator_mode
              item.expected_event_id = website.rollout_events.maximum(:id)
            end
            item.status = "running"
            item.started_at ||= Time.current
            item.phase_started_at = Time.current
            item.deadline_at = Time.current + TransitionRun::LEASE + 2.minutes
            item.phase_token = token = SecureRandom.hex(16)
            run = TransitionRun.request!(website: website, options: item.batch.check_options, workflow_item: item).run
            item.public_send("#{item.phase == 'postcheck' ? 'post' : 'pre'}_run=", run)
            item.save!
          end
        end
      end
      item.batch.enqueue_next! if item.terminal?
      token
    end

    def migrated?(website)
      inventories = WebsiteInventoryFreshness.for_websites([website.id])
      WebsiteValidationHistory.for_websites([website], inventories: inventories).fetch(website.id).milestone == "migrated"
    end

    def finish_phase(item, token, run)
      dispatch_post = false
      changed = owned(item, token) do |website|
        raise TransitionRun::Cancelled, TransitionRun::CANCELLED_MESSAGE if item.cancel_requested_at?

        next unless item.phase_started_at && item.current_run&.id == run.id

        raise "This site is no longer eligible for event-site migration" unless EventSiteSelection.eligible_ids([website]).include?(website.id)
        unless website.latest_transition_run&.id == run.id && website.transition_run_blocker(run).nil?
          raise "The check was superseded or configuration changed. Run a new workflow."
        end
        status = TransitionStatus.for_completed_run(website: website, run: run)
        item.phase_results = item.phase_results.merge(item.phase => comparison_result(run, website))
        item.save!
        unless status.status == :ready
          summary = TransitionFetchSummary.call(fetch_details: run.transition_evidences.find_by(check_kind: "fetch_parity")&.details,
            statement_details: run.transition_evidences.find_by(check_kind: "statement_delta")&.details)
          issue = summary.issues.first
          reason = issue ? "#{issue[:backend]}: #{issue[:reason]} — #{issue[:url]}" :
            ((status.blockers + status.warnings).first.presence || "Comparison is incomplete or requires review.")
          # Recover outside this transaction to keep ownership checks uniform.
          raise reason
        end
        if item.phase == "precheck"
          result = @rollout.call(website: website, to_mode: "active", actor: item.actor,
            reason: "All required pre-activation checks passed in run ##{run.id}")
          raise result.errors.join(", ") unless result.success?
          item.update!(phase: "postcheck", phase_started_at: nil, expected_mode: "active",
            expected_event_id: website.rollout_events.maximum(:id),
            phase_results: item.phase_results.merge("activation" => { state: "completed", at: Time.current.iso8601(6) }))
          dispatch_post = true
        else
          reason = if item.batch.audit?
            "Thorough Active audit passed."
          elsif item.pre_run_id
            "Pre-activation and active-path verification passed."
          else
            "Active-path verification passed."
          end
          finish(item, website, "passed", reason)
        end
      end
      if dispatch_post
        job = SiteTransitionJob.perform_later(item.id, phase: "postcheck")
        raise "Could not queue active-path verification" unless job
      elsif changed
        item.batch.enqueue_next!
      end
    end

    def owned(item, token)
      website = item.website&.reload
      unless website
        item.reload
        return false if item.terminal?
        item.update!(status: "cancelled", phase: "finished", completed_at: Time.current, reason: "Website was deleted")
        return true
      end
      changed = false
      website.with_lock do
        item.with_lock do
          next if item.terminal? || item.phase_token != token
          changed = true
          if matches_operator_state?(item, website)
            yield website
          else
            finish_after_operator_change(item, website)
          end
        end
      end
      changed
    end

    def matches_operator_state?(item, website)
      website.distillator_mode == item.expected_mode && website.rollout_events.maximum(:id) == item.expected_event_id
    end

    def finish_after_operator_change(item, website)
      if item.cancel_requested_at? && (run = item.current_run)
        run.fail!(TransitionRun::CANCELLED_MESSAGE)
        run.transition_checkpoints.delete_all
      end
      finish(item, website, "cancelled", "The operator changed the website mode; automation stopped without changing it.")
    end

    def comparison_result(run, website)
      return { run_id: run.id, state: run.status, reason: run.error_message } unless run.status == "completed"
      status = TransitionStatus.for_completed_run(website: website, run: run)
      { run_id: run.id, state: status.status.to_s, fetch: status.fetch, statements: status.statements,
        export: status.export, blockers: status.blockers, warnings: status.warnings }
    end

    def finish(item, website, status, reason)
      resolution = FetchMode.rollout_resolution_object(website: website)
      item.update!(status: status, phase: "finished", completed_at: Time.current, phase_started_at: nil,
        final_mode: website.distillator_mode, final_backend: resolution.active_backend.to_s, reason: reason)
    end
  end
end
