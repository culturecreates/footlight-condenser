class ObjectClassesController < ApplicationController
  before_action :set_object_class, only: [:show, :edit, :update, :destroy]

  # GET /object_classes
  # GET /object_classes.json
  def index
    @object_classes = ObjectClass.all
  end

  # GET /object_classes/1
  # GET /object_classes/1.json
  def show
  end

  # GET /object_classes/new
  def new
    @object_class = ObjectClass.new
  end

  # GET /object_classes/1/edit
  def edit
  end

  # POST /object_classes
  # POST /object_classes.json
  def create
    @object_class = ObjectClass.new(object_class_params)

    respond_to do |format|
      if @object_class.save
        format.html { redirect_to @object_class, notice: 'Object class was successfully created.' }
        format.json { render :show, status: :created, location: @object_class }
      else
        format.html { render :new }
        format.json { render json: @object_class.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /object_classes/1
  # PATCH/PUT /object_classes/1.json
  def update
    respond_to do |format|
      if @object_class.update(object_class_params)
        format.html { redirect_to @object_class, notice: 'Object class was successfully updated.' }
        format.json { render :show, status: :ok, location: @object_class }
      else
        format.html { render :edit }
        format.json { render json: @object_class.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /object_classes/1
  # DELETE /object_classes/1.json
  def destroy
    @object_class.destroy
    respond_to do |format|
      format.html { redirect_to object_classes_url, notice: 'Object class was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_object_class
      @object_class = ObjectClass.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def object_class_params
      params.require(:object_class).permit(:name)
    end
end
