class PlacesController < ApplicationController
    include HarmonizedIndexParams

    def index
        # GET /places.json?seedurl=

        # data structures:
        # 1. one place with one link:  "["Wednesday @ Salle André-Mathieu", "Place", ["Salle André-Mathieu", "adr:salle-andre-mathieu"]]"
        # 2. one place with two links: "["Wednesday @ Salle André-Mathieu", "Place", ["Salle André-Mathieu", "adr:salle-andre-mathieu","Annexe André-Mathieu", "adr:annexe-mathieu"]]"
        # 3. no place:  "[]"
        # 4. two places each with one link:  "[["Saturday @ Théâtre des Muses", "Place", ["Théâtre des Muses", "http://laval.footlight.io/resource/theatre-des-muses"]], ["Monday @ Théâtre des Muses", "Place", ["Théâtre des Muses", "http://laval.footlight.io/resource/theatre-des-muses"]]]"
        
 
        index_params = harmonized_index_params(
          allowed_filters: Places::IndexQuery::FILTER_KEYS,
          allowed_sorts: Places::IndexQuery::SORT_COLUMNS,
          default_sort: Places::IndexQuery::DEFAULT_SORT,
          default_direction: Places::IndexQuery::DEFAULT_DIRECTION,
          default_per_page: Places::IndexQuery::DEFAULT_PER_PAGE,
          max_per_page: Places::IndexQuery::MAX_PER_PAGE
        )
        index_params[:filters] = index_params[:filters].merge(seedurl: params[:seedurl])

        canonical = harmonized_index_canonical_params(
          index_params,
          default_sort: Places::IndexQuery::DEFAULT_SORT,
          default_direction: Places::IndexQuery::DEFAULT_DIRECTION,
          default_per_page: Places::IndexQuery::DEFAULT_PER_PAGE,
          preserve: { seedurl: params[:seedurl] }
        )
        raw = harmonized_index_raw_params(allowed_filters: Places::IndexQuery::FILTER_KEYS, preserve: %w[seedurl sort direction page per_page])
        return redirect_to(places_path(canonical)) if canonical != raw

        @filters = index_params[:filters]
        @sort = index_params[:sort]
        @direction = index_params[:direction]
        @pagination = { page: index_params[:page], per_page: index_params[:per_page] }
        @sortable_filters = @filters.except(:seedurl).merge(per_page: @pagination[:per_page])
        @place_table_headers = HarmonizedTableHeaders.places
        @places = Places::IndexQuery.call(
          filters: @filters,
          sort: @sort,
          direction: @direction,
          page: @pagination[:page],
          per_page: @pagination[:per_page]
        )
    end


private

    def get_places 
        return Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Location", rdfs_class: 1}, websites:  {seedurl: params[:seedurl]} }  }  ).pluck(:rdf_uri, :cache, "sources.language", :url)
    end

end
