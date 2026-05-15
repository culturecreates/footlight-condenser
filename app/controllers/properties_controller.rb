class PropertiesController < ApplicationController
  include HarmonizedIndexParams

  before_action :set_property, only: [:show, :edit, :update, :destroy]
  skip_before_action :verify_authenticity_token

  # GET /properties
  # GET /properties.json
  def index
    index_params = harmonized_index_params(
      allowed_filters: Properties::IndexQuery::FILTER_KEYS,
      allowed_sorts: Properties::IndexQuery::SORT_COLUMNS.keys,
      default_sort: Properties::IndexQuery::DEFAULT_SORT,
      default_direction: Properties::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Properties::IndexQuery::DEFAULT_PER_PAGE,
      max_per_page: Properties::IndexQuery::MAX_PER_PAGE
    )

    canonical = harmonized_index_canonical_params(
      index_params,
      default_sort: Properties::IndexQuery::DEFAULT_SORT,
      default_direction: Properties::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Properties::IndexQuery::DEFAULT_PER_PAGE
    )
    raw = harmonized_index_raw_params(allowed_filters: Properties::IndexQuery::FILTER_KEYS, preserve: %w[sort direction page per_page])
    return redirect_to(properties_path(canonical)) if request.format.html? && canonical != raw

    @filters = index_params[:filters]
    @sort = index_params[:sort]
    @direction = index_params[:direction]
    @pagination = { page: index_params[:page], per_page: index_params[:per_page] }
    @sortable_filters = @filters.merge(per_page: @pagination[:per_page])
    @property_table_headers = HarmonizedTableHeaders.properties
    @properties = Properties::IndexQuery.call(
      filters: @filters,
      sort: @sort,
      direction: @direction,
      page: @pagination[:page],
      per_page: @pagination[:per_page]
    )
  end

  # GET /properties/1
  # GET /properties/1.json
  def show
  end

  # GET /properties/new
  def new
    @property = Property.new
  end

  # GET /properties/1/edit
  def edit
  end

  # Review all statements belonging to a PROPERTY ID (can include en and fr sources) and a website seedurl
  # PATCH/PUT /properties/1/review_all_statements.json?seedurl=&status_origin=
  def review_all_statements
    # get all statements that are linked to source id
    statements = Statement.includes(source: :website).where(sources: { property_id: params[:id], websites: { seedurl: params[:seedurl] }}, status: ["updated","initial"], selected_individual: true)
    statements.each do |stat|
      stat.update(status: 'ok', status_origin: params[:status_origin])
    end
    # TODO: Handle errors?
    respond_to do |format|
        format.json {  render :plain => { success: true }.to_json, status: :ok, content_type: 'application/json' }
    end
  end


  # POST /properties
  # POST /properties.json
  def create
    @property = Property.new(property_params)

    respond_to do |format|
      if @property.save
        format.html { redirect_to @property, notice: 'Property was successfully created.' }
        format.json { render :show, status: :created, location: @property }
      else
        format.html { render :new }
        format.json { render json: @property.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /properties/1
  # PATCH/PUT /properties/1.json
  def update
    respond_to do |format|
      if @property.update(property_params)
        format.html { redirect_to @property, notice: 'Property was successfully updated.' }
        format.json { render :show, status: :ok, location: @property }
      else
        format.html { render :edit }
        format.json { render json: @property.errors, status: :unprocessable_entity }
      end
    end
  end


  # DELETE /properties/1
  # DELETE /properties/1.json
  def destroy
    @property.destroy
    respond_to do |format|
      format.html { redirect_to properties_url, notice: 'Property was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_property
      @property = Property.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def property_params
      params.require(:property).permit(:label, :value_datatype,  :expected_class, :uri, :rdfs_class_id)
    end
end
