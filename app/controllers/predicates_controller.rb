class PredicatesController < ApplicationController
  before_action :set_predicate, only: [:show, :edit, :update, :destroy]

  # GET /predicates
  # GET /predicates.json
  def index
    @predicates = Predicate.all
  end

  # GET /predicates/1
  # GET /predicates/1.json
  def show
  end

  # GET /predicates/new
  def new
    @predicate = Predicate.new
  end

  # GET /predicates/1/edit
  def edit
  end

  # POST /predicates
  # POST /predicates.json
  def create
    @predicate = Predicate.new(predicate_params)

    respond_to do |format|
      if @predicate.save
        format.html { redirect_to @predicate, notice: 'Predicate was successfully created.' }
        format.json { render :show, status: :created, location: @predicate }
      else
        format.html { render :new }
        format.json { render json: @predicate.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /predicates/1
  # PATCH/PUT /predicates/1.json
  def update
    respond_to do |format|
      if @predicate.update(predicate_params)
        format.html { redirect_to @predicate, notice: 'Predicate was successfully updated.' }
        format.json { render :show, status: :ok, location: @predicate }
      else
        format.html { render :edit }
        format.json { render json: @predicate.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /predicates/1
  # DELETE /predicates/1.json
  def destroy
    @predicate.destroy
    respond_to do |format|
      format.html { redirect_to predicates_url, notice: 'Predicate was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_predicate
      @predicate = Predicate.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def predicate_params
      params.require(:predicate).permit(:label, :language, :object_datatype, :uri)
    end
end
