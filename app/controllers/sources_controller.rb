class SourcesController < ApplicationController
  before_action :set_source, only: [:show, :edit, :update, :destroy]

  # GET /sources
  # GET /sources.json
  def index

    seedurl = params[:seedurl] ||  cookies[:seedurl]
    if seedurl
      @sources = Source.where(website_id: Website.where(seedurl: seedurl).first.id).order(:property_id, :language, selected: :desc)
    else
      @sources = Source.all
    end
    @rdfs_classes = RdfsClass.all
  end

  # GET /sources/website?id=
  def website
    @sources = Source.where(website_id: params[:id])
    @website = Website.where(id: params[:id]).first
  end

  # GET /sources/1
  # GET /sources/1.json
  def show
  end


  # GET /sources/new[?rdfs_class_id=]
  def new
    @source = Source.new
    @websites = Website.all
    @properties = Property.all
    @rdfs_class_id = params[:rdfs_class_id] || 1 #default to event class
    @rdfs_class_name = RdfsClass.find(@rdfs_class_id).name
  end

  # GET /sources/1/edit
  def edit
    @websites = Website.all
    @properties = Property.all
    @rdfs_class_id = @source.property.rdfs_class_id
    @rdfs_class_name = @source.property.rdfs_class.name
  end

  # POST /sources
  # POST /sources.json
  def create
    @source = Source.new(source_params)

    respond_to do |format|
      if @source.save
        format.html { redirect_to @source, notice: 'Source was successfully created.' }
        format.json { render :show, status: :created, location: @source }
      else
        format.html { render :new }
        format.json { render json: @source.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /sources/1
  # PATCH/PUT /sources/1.json
  def update
    respond_to do |format|
      if @source.update(source_params)
        format.html { redirect_to @source, notice: 'Source was successfully updated.' }
        format.json { render :show, status: :ok, location: @source }
      else
        format.html { render :edit }
        format.json { render json: @source.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /sources/1
  # DELETE /sources/1.json
  def destroy
    @source.destroy
    respond_to do |format|
      format.html { redirect_to sources_url, notice: 'Source was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_source
      @source = Source.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def source_params
      params.require(:source).permit(:algorithm_value, :language, :selected, :selected_by, :next_step, :render_js, :property_id, :website_id)
    end
end
