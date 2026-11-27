class MessagesController < ApplicationController
  include HarmonizedIndexParams
  PER_PAGE = 100
  skip_before_action :verify_authenticity_token, :authenticate
  before_action :set_message, only: [:show, :edit, :update, :destroy]

  # GET /messages
  # GET /messages.json
  def index
    options = harmonized_index_params(allowed_filters: [:seedurl], allowed_sorts: ["created_at"],
      default_sort: "created_at", default_direction: "desc", default_per_page: PER_PAGE, max_per_page: PER_PAGE)
    @seedurl = options[:filters][:seedurl].presence
    @seedurl = nil if @seedurl == "all"
    scope = Message.order(created_at: options[:direction], id: options[:direction])
    scope = scope.where(artifact: @seedurl) if @seedurl
    @messages = scope.paginate(page: options[:page], per_page: options[:per_page])
    @pagination_params = { seedurl: @seedurl, per_page: options[:per_page], direction: options[:direction] }.compact

    # Databus callback artifacts are website seedurls. Include historical
    # artifacts as well, so deleting a website does not hide its message history.
    sites = Website.where.not(seedurl: [nil, ""]).order(:name, :id).pluck(:name, :seedurl).uniq { |_, seedurl| seedurl }
    artifacts = Message.where.not(artifact: [nil, ""]).distinct.pluck(:artifact)
    known = sites.map(&:last)
    @site_options = sites.map { |name, seedurl| [name.present? ? "#{name} (#{seedurl})" : seedurl, seedurl] }
    @site_options.concat((artifacts - known).sort.map { |artifact| [artifact, artifact] })
  end

  # GET /messages/1
  # GET /messages/1.json
  def show
  end

  # GET /messages/new
  def new
    @message = Message.new
  end

  # POST /webhook.json
  # Use this for callback URL with Artsdata Databus
  def webhook
    @message = Message.new
    @message.message = params[:message]
    @message.artifact = params[:artifact]
    respond_to do |format|
      if @message.save
        format.html { redirect_to @message, notice: 'Message was successfully created.' }
        format.json { render :show, status: :created, location: @message }
      else
        format.html { render :new }
        format.json { render json: @message.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /messages/1/edit
  def edit
  end

  # POST /messages
  # POST /messages.json
  def create
    @message = Message.new(message_params)

    respond_to do |format|
      if @message.save
        format.html { redirect_to @message, notice: 'Message was successfully created.' }
        format.json { render :show, status: :created, location: @message }
      else
        format.html { render :new }
        format.json { render json: @message.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /messages/1
  # PATCH/PUT /messages/1.json
  def update
    respond_to do |format|
      if @message.update(message_params)
        format.html { redirect_to @message, notice: 'Message was successfully updated.' }
        format.json { render :show, status: :ok, location: @message }
      else
        format.html { render :edit }
        format.json { render json: @message.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /messages/1
  # DELETE /messages/1.json
  def destroy
    @message.destroy
    respond_to do |format|
      format.html { redirect_to messages_url, notice: 'Message was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_message
      @message = Message.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def message_params
      params.require(:message).permit(:message, :artifact)
    end
end
