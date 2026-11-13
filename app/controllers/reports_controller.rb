class ReportsController < ApplicationController
    include HarmonizedIndexParams

    def source
        # GET /reports/source.json?source_id=
        params[:startDate]  # "2018-01-01"
        params[:endDate]   # "2021-01-01"
    
        index_params = harmonized_index_params(
          allowed_filters: Reports::IndexQuery::FILTER_KEYS,
          allowed_sorts: Reports::IndexQuery::SORT_COLUMNS,
          default_sort: Reports::IndexQuery::DEFAULT_SORT,
          default_direction: Reports::IndexQuery::DEFAULT_DIRECTION,
          default_per_page: Reports::IndexQuery::DEFAULT_PER_PAGE,
          max_per_page: Reports::IndexQuery::MAX_PER_PAGE
        )
        index_params[:filters] = index_params[:filters].merge(source_id: params[:source_id])

        canonical = harmonized_index_canonical_params(
          index_params,
          default_sort: Reports::IndexQuery::DEFAULT_SORT,
          default_direction: Reports::IndexQuery::DEFAULT_DIRECTION,
          default_per_page: Reports::IndexQuery::DEFAULT_PER_PAGE,
          preserve: { source_id: params[:source_id] }
        )
        raw = harmonized_index_raw_params(allowed_filters: Reports::IndexQuery::FILTER_KEYS, preserve: %w[source_id sort direction page per_page])
        return redirect_to(source_reports_path(canonical)) if request.format.html? && canonical != raw

        source = Source.where(id: params[:source_id]).first
        @page_title = "Report for #{source.property.label} (source #{source.id})"
        @filters = index_params[:filters]
        @sort = index_params[:sort]
        @direction = index_params[:direction]
        @pagination = { page: index_params[:page], per_page: index_params[:per_page] }
        @sortable_filters = @filters.except(:source_id).merge(per_page: @pagination[:per_page])
        @report_table_headers = HarmonizedTableHeaders.reports

        @report_rows = Reports::IndexQuery.call(
          filters: @filters,
          sort: @sort,
          direction: @direction,
          page: @pagination[:page],
          per_page: @pagination[:per_page]
        )
    end
end
