module Distillator
  class ShadowReportsController < ApplicationController
    include HarmonizedIndexParams

    def index
      index_params = harmonized_index_params(
        allowed_filters: Distillator::ShadowReportQuery::FILTER_KEYS,
        allowed_sorts: Distillator::ShadowReportQuery::SORT_COLUMNS,
        default_sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
        default_direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
        default_per_page: Distillator::ShadowReportQuery::DEFAULT_PER_PAGE,
        max_per_page: Distillator::ShadowReportQuery::MAX_PER_PAGE
      )

      canonical = harmonized_index_canonical_params(
        index_params,
        default_sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
        default_direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
        default_per_page: Distillator::ShadowReportQuery::DEFAULT_PER_PAGE
      )
      raw = harmonized_index_raw_params(
        allowed_filters: Distillator::ShadowReportQuery::FILTER_KEYS,
        preserve: %w[sort direction page per_page]
      )
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
  end
end
