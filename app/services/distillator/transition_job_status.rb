require "sidekiq/api"

module Distillator
  class TransitionJobStatus
    def initialize(run:, workflow:, now: Time.current)
      @run, @workflow, @now = run, workflow, now
    end

    def message
      unless ActiveJob::Base.queue_adapter_name.to_s == "sidekiq"
        return "Waiting for a worker to start this check." unless @run&.status == "running"
        return
      end

      running = Sidekiq::WorkSet.new.filter_map { |_, _, work| job_kind(work.job) }
      return if running.include?(:check)
      return "Automatic recovery is running." if running.include?(:recovery)
      # A newly claimed job may not be visible until Sidekiq's next heartbeat.
      return if @run&.status == "running" && @now - (@run.started_at || @run.requested_at) < 15.seconds

      queued = queue_names.flat_map do |name|
        Sidekiq::Queue.new(name).filter_map { |job| job_kind(job) }
      end
      return "Waiting in the Sidekiq queue for a worker to start this check." if queued.include?(:check)
      return "The recovery job is queued. Waiting for a Sidekiq worker." if queued.include?(:recovery)

      future_job = next_scheduled_job
      return scheduled_message(*future_job) if future_job

      if @workflow&.deadline_at
        "Sidekiq reports no job for this workflow. The recorded recovery deadline is #{local_time(@workflow.deadline_at)}."
      elsif @run&.status == "running"
        "Sidekiq reports no job for this run. Its lease expires at #{local_time(@run.requested_at + TransitionRun::LEASE)}."
      else
        "Sidekiq reports no job for this check yet."
      end
    rescue StandardError
      "Sidekiq queue status is unavailable."
    end

    private

    def queue_names
      classes = @workflow ? [SiteTransitionJob, SiteTransitionWatchdogJob] : [TransitionCheckJob]
      classes.map { |job| job.new.queue_name }.uniq
    end

    def next_scheduled_job
      prefix = @workflow ? "Distillator::SiteTransition" : "Distillator::TransitionCheckJob"
      [Sidekiq::ScheduledSet, Sidekiq::RetrySet].flat_map do |set|
        set.new.scan(prefix).filter_map do |job|
          kind = job_kind(job)
          [kind, job.at] if kind
        end
      end.min_by(&:last)
    end

    def job_kind(job)
      payload = job.item
      wrapped_args = payload["args"]
      return unless wrapped_args.is_a?(Array) && wrapped_args.first.is_a?(Hash)

      args = wrapped_args.first["arguments"]
      return unless args.is_a?(Array)

      case payload["wrapped"]
      when "Distillator::TransitionCheckJob"
        :check if @run && !@workflow && args.last.is_a?(Hash) && args.last["run_id"].to_s == @run.id.to_s
      when "Distillator::SiteTransitionJob"
        :check if workflow_job?(args) && args.last.is_a?(Hash) && workflow_phases.include?(args.last["phase"])
      when "Distillator::SiteTransitionWatchdogJob"
        :recovery if workflow_job?(args)
      end
    end

    def workflow_job?(args)
      @workflow && args.first.to_s == @workflow.id.to_s && (!@run || @workflow.current_run&.id == @run.id)
    end

    def workflow_phases
      @workflow.phase == "precheck" ? %w[queued precheck] : [@workflow.phase]
    end

    def scheduled_message(kind, time)
      name = kind == :recovery ? "automatic recovery" : "the next check"
      if time > @now
        "Waiting for #{name}. Sidekiq scheduled it for #{local_time(time)}."
      else
        "Waiting for #{name}. It was due at #{local_time(time)} and is still in Sidekiq’s scheduled or retry set."
      end
    end

    def local_time(time) = time.in_time_zone.strftime("%b %-d, %H:%M:%S %Z")
  end
end
