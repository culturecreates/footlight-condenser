class MonitoringController < ApplicationController
  def index
    @status = params[:status].in?(%w[open resolved all]) ? params[:status] : "open"
    @seedurl = params[:seedurl].presence
    @seedurl = nil if @seedurl == "all"
    scope = MonitoringIssue.all
    scope = scope.open_issues if @status == "open"
    scope = scope.where.not(resolved_at: nil) if @status == "resolved"
    scope = scope.where(seedurl: @seedurl) if @seedurl
    @issues = scope.order(last_seen_at: :desc, id: :desc).paginate(page: params[:page].to_i.clamp(1, 100_000), per_page: 100)
    @sites = MonitoringIssue.distinct.order(:seedurl).pluck(:seedurl)
    respond_to do |format|
      format.html do
        @diagnostic_targets = diagnostic_targets
        render :index
      end
      format.json do
        render json: { issues: @issues.as_json(only: %i[id seedurl website_name url source_id statement_id property_name message
          occurrences first_seen_at last_seen_at resolved_at kind preprocessing_policy_id]), sites: @sites,
          pagination: { page: @issues.current_page, total_pages: @issues.total_pages, total_entries: @issues.total_entries, per_page: 100 } }
      end
    end
  end

  private

  def diagnostic_targets
    {
      websites: Website.where(seedurl: @issues.map(&:seedurl)).group_by(&:seedurl),
      sources: Source.where(id: @issues.map(&:source_id)).ids.to_set,
      statements: Statement.where(id: @issues.filter_map(&:statement_id)).ids.to_set,
      policies: PreprocessingPolicy.where(id: @issues.filter_map(&:preprocessing_policy_id)).ids.to_set
    }
  end
end
