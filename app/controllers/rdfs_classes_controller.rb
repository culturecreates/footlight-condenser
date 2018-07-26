class RdfsClassesController < ApplicationController
  before_action :set_rdfs_class, only: [:show, :edit, :update, :destroy]

  # GET /rdfs_classes
  # GET /rdfs_classes.json
  def index
    @rdfs_classes = RdfsClass.all
  end

  # GET /rdfs_classes/1
  # GET /rdfs_classes/1.json
  def show
  end

  # GET /rdfs_classes/new
  def new
    @rdfs_class = RdfsClass.new
  end

  # GET /rdfs_classes/1/edit
  def edit
  end

  # POST /rdfs_classes
  # POST /rdfs_classes.json
  def create
    @rdfs_class = RdfsClass.new(rdfs_class_params)

    respond_to do |format|
      if @rdfs_class.save
        format.html { redirect_to @rdfs_class, notice: 'Rdfs class was successfully created.' }
        format.json { render :show, status: :created, location: @rdfs_class }
      else
        format.html { render :new }
        format.json { render json: @rdfs_class.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /rdfs_classes/1
  # PATCH/PUT /rdfs_classes/1.json
  def update
    respond_to do |format|
      if @rdfs_class.update(rdfs_class_params)
        format.html { redirect_to @rdfs_class, notice: 'Rdfs class was successfully updated.' }
        format.json { render :show, status: :ok, location: @rdfs_class }
      else
        format.html { render :edit }
        format.json { render json: @rdfs_class.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /rdfs_classes/1
  # DELETE /rdfs_classes/1.json
  def destroy
    @rdfs_class.destroy
    respond_to do |format|
      format.html { redirect_to rdfs_classes_url, notice: 'Rdfs class was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_rdfs_class
      @rdfs_class = RdfsClass.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def rdfs_class_params
      params.require(:rdfs_class).permit(:name)
    end
end
