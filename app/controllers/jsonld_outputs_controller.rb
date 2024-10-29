class JsonldOutputsController < ApplicationController
  before_action :set_jsonld_output, only: %i[ show edit update destroy ]

  # GET /jsonld_outputs or /jsonld_outputs.json
  def index
    @jsonld_outputs = JsonldOutput.all
  end

  # GET /jsonld_outputs/1 or /jsonld_outputs/1.json
  def show
  end

  # GET /jsonld_outputs/new
  def new
    @jsonld_output = JsonldOutput.new
  end

  # GET /jsonld_outputs/1/edit
  def edit
  end

  # POST /jsonld_outputs or /jsonld_outputs.json
  def create
    @jsonld_output = JsonldOutput.new(jsonld_output_params)

    respond_to do |format|
      if @jsonld_output.save
        format.html { redirect_to jsonld_output_url(@jsonld_output), notice: "Jsonld output was successfully created." }
        format.json { render :show, status: :created, location: @jsonld_output }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @jsonld_output.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /jsonld_outputs/1 or /jsonld_outputs/1.json
  def update
    respond_to do |format|
      if @jsonld_output.update(jsonld_output_params)
        format.html { redirect_to jsonld_output_url(@jsonld_output), notice: "Jsonld output was successfully updated." }
        format.json { render :show, status: :ok, location: @jsonld_output }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @jsonld_output.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /jsonld_outputs/1 or /jsonld_outputs/1.json
  def destroy
    @jsonld_output.destroy

    respond_to do |format|
      format.html { redirect_to jsonld_outputs_url, notice: "Jsonld output was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_jsonld_output
      @jsonld_output = JsonldOutput.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def jsonld_output_params
      params.require(:jsonld_output).permit(:name, :frame)
    end
end
