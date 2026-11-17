class PreprocessingPoliciesController < ApplicationController
  before_action :set_policy, only: [:edit, :update, :run]

  def index
    @policies = PreprocessingPolicy.order(:seedurl, :statement_id).paginate(page: params[:page].to_i.clamp(1, 100_000), per_page: 100)
    @issue_counts = MonitoringIssue.open_issues.where(preprocessing_policy_id: @policies.map(&:id)).group(:preprocessing_policy_id).count
    fingerprints = @policies.map { |policy| MonitoringIssue.fingerprint_for(policy) }
    dsl_issues = MonitoringIssue.open_issues.where(fingerprint: fingerprints).pluck(:fingerprint)
    @policies.each { |policy| @issue_counts[policy.id] = @issue_counts.fetch(policy.id, 0) + (dsl_issues.include?(MonitoringIssue.fingerprint_for(policy)) ? 1 : 0) }
  end

  def new
    @policy = PreprocessingPolicy.new(statement_id: params[:statement_id], expected_seedurl: params[:expected_seedurl])
    render :edit
  end

  def create
    @policy = PreprocessingPolicy.new(policy_params.merge(enabled: false))
    if @policy.save
      redirect_to edit_preprocessing_policy_path(@policy), notice: "Draft policy created. Inspect the target DSL and upstream IDs before enabling."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @policy.with_lock { @policy.update!(policy_params.except(:statement_id, :expected_seedurl)) }
    Preprocessing::Monitor.evaluate(@policy)
    redirect_to edit_preprocessing_policy_path(@policy), notice: "Preprocessing policy saved. Existing website schedules are unchanged."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def run
    run = Preprocessing::Dispatcher.dispatch(@policy, force: true)
    redirect_to edit_preprocessing_policy_path(@policy), notice: run ? "Refresh queued as run ##{run.id}." : "Policy is disabled or a refresh is already queued/running."
  rescue StandardError => error
    Preprocessing::Monitor.evaluate(@policy.reload)
    Rails.logger.error("[Preprocessing] Operator enqueue failed policy=#{@policy.id} #{error.class}")
    redirect_to edit_preprocessing_policy_path(@policy), alert: "Could not queue refresh. Inspect the latest attempt and retry; no successful refresh was recorded."
  end

  private

  def set_policy
    @policy = PreprocessingPolicy.find(params[:id])
  end

  def policy_params
    permitted = params.require(:preprocessing_policy).permit(:statement_id, :expected_seedurl, :enabled,
      :inputs_verified, :monitoring_enabled, :interval_hours, :stale_after_hours, :input_ids_text)
    if permitted.key?(:input_ids_text)
      text = permitted.delete(:input_ids_text).to_s
      ids = text.split(/[\s,]+/).reject(&:empty?)
      permitted[:input_statement_ids] = ids.map { |id| id.match?(/\A[1-9]\d*\z/) ? id.to_i : id }
    end
    permitted
  end
end
