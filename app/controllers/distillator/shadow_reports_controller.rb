module Distillator
  class ShadowReportsController < ApplicationController
    include HarmonizedIndexParams

    def index
      index_params = harmonized_index_params(
        allowed_filters: Distillator::ShadowReportQuery::FILTER_KEYS,
        allowed_sorts: Distillator::ShadowReportQuery::SORT_COLUMNS,
        default_sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
        default_direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
        default_per_page: Distillator::ShadowReportQuery::DEFAULT_LIMIT,
        max_per_page: Distillator::ShadowReportQuery::MAX_LIMIT
      )
      index_params[:filters] = index_params[:filters].to_h.symbolize_keys
      index_params[:filters][:mode] = index_params[:filters][:mode].presence || "shadow"
      index_params[:per_page] = normalized_limit_param(params[:limit].presence || params[:per_page])

      canonical = harmonized_index_canonical_params(
        index_params,
        default_sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
        default_direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
        default_per_page: Distillator::ShadowReportQuery::DEFAULT_LIMIT
      )
      canonical.delete("mode") if params[:mode].blank? && index_params[:filters][:mode] == "shadow"
      canonical["limit"] = canonical.delete("per_page") if canonical.key?("per_page")
      raw = harmonized_index_raw_params(
        allowed_filters: Distillator::ShadowReportQuery::FILTER_KEYS,
        preserve: %w[sort direction page limit per_page]
      )
      raw["limit"] = raw.delete("per_page") if raw["limit"].blank? && raw["per_page"].present?
      raw.except!("per_page")
      return redirect_to(distillator_shadow_report_path(canonical)) if request.format.html? && canonical != raw

      @filters = index_params[:filters]
      @sort = index_params[:sort]
      @direction = index_params[:direction]
      @report = Distillator::ShadowReport.call(**index_params)
      @rows = @report.rows
      @summary_counts = @report.summary_counts
      @global_summary_counts = @report.global_summary_counts
      @dashboard_counts = @report.dashboard_counts
      @blocker_counts = @report.blocker_counts
      @pagination = {
        page: @report.page,
        per_page: @report.per_page,
        total_count: @report.total_count,
        total_pages: @report.total_pages
      }
    end

    def show
      @website = Website.find(params[:id])
      @detail = Distillator::ShadowSiteDetail.call(website: @website)
    end

    private

    def normalized_limit_param(value)
      requested = value.to_i
      requested = Distillator::ShadowReportQuery::DEFAULT_LIMIT unless requested.positive?
      [requested, Distillator::ShadowReportQuery::MAX_LIMIT].min
    end
  end
end
