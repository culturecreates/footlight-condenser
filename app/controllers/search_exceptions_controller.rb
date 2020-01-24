class SearchExceptionsController < ApplicationController
  before_action :set_search_exception, only: [:show, :edit, :update, :destroy]

  # GET /search_exceptions
  # GET /search_exceptions.json
  def index
    @search_exceptions = SearchException.all
  end

  # GET /search_exceptions/1
  # GET /search_exceptions/1.json
  def show
  end

  # GET /search_exceptions/new
  def new
    @search_exception = SearchException.new
  end

  # GET /search_exceptions/1/edit
  def edit
  end

  # POST /search_exceptions
  # POST /search_exceptions.json
  def create
    @search_exception = SearchException.new(search_exception_params)

    respond_to do |format|
      if @search_exception.save
        format.html { redirect_to @search_exception, notice: 'Search exception was successfully created.' }
        format.json { render :show, status: :created, location: @search_exception }
      else
        format.html { render :new }
        format.json { render json: @search_exception.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /search_exceptions/1
  # PATCH/PUT /search_exceptions/1.json
  def update
    respond_to do |format|
      if @search_exception.update(search_exception_params)
        format.html { redirect_to @search_exception, notice: 'Search exception was successfully updated.' }
        format.json { render :show, status: :ok, location: @search_exception }
      else
        format.html { render :edit }
        format.json { render json: @search_exception.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /search_exceptions/1
  # DELETE /search_exceptions/1.json
  def destroy
    @search_exception.destroy
    respond_to do |format|
      format.html { redirect_to search_exceptions_url, notice: 'Search exception was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_search_exception
      @search_exception = SearchException.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def search_exception_params
      params.require(:search_exception).permit(:name, :rdfs_class_id)
    end
end
