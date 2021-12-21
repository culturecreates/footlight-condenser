class SourcesController < ApplicationController
  before_action :set_source, only: [:show, :edit, :update, :destroy]
  skip_before_action :verify_authenticity_token

  # GET /sources
  # GET /sources.json
  def index
    seedurl = params[:seedurl] ||  cookies[:seedurl]
    if seedurl
      @sources = Source.where(website_id: Website.where(seedurl: seedurl).first.id).order(selected: :desc).order(:property_id, :language)
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
  # manually create sources for all websites using:
  #   > website_hash = Website.all.map {|w| {website_id: w.id}}
  #   > Source.create(website_hash) {|s| s.algorithm_value = ''; s.selected = true; s.property_id=XX; s.render_js = false ; s.language = ''}
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

  # PATCH/PUT /sources/1/review_all_statements.json
  def review_all_statements
    # get all statements that are linked to source id
    statements = Statement.includes(:source).where(sources: { property_id: params[:id] }, status: ["updated","initial"], selected_individual: true)
    respond_to do |format|
      if statements.update_all(status: 'ok')
        format.json { render status: :ok }
      else
        format.json { render json: statements.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /sources/1
  # DELETE /sources/1.json
  # Manually delete on Heroku using:
  #    > Source.where(algorithm_value: ' ', created_at: [Time.now - 1.hour..Time.now + 10.years]).delete_all
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
    params.require(:source).permit(:algorithm_value, :label, :language, :selected, :selected_by, :next_step, :render_js, :property_id, :website_id, :auto_review)
  end
end
