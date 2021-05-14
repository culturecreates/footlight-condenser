class DatabusController < ApplicationController
  # GET /databus
  # List files on S3
  def index
    @contents = []
    begin
      client = Aws::S3::Client.new(region: "ca-central-1", access_key_id: ENV["ACCESS_KEY_ID"], secret_access_key: ENV["SECRET_ACCESS_KEY"])
      result = client.list_objects(
        bucket: "data.culturecreates.com",
        max_keys: 200,
        prefix: 'databus/culture-creates/footlight/'
      )
      @contents = result.contents if result.contents
    rescue Aws::Sigv4::Errors::MissingCredentialsError => e
      flash.now[:notice] = e.message
    end
  end

  # POST /databus?jsonld=&artifact=&version=&file=
  # Save JSON-LD on S3
  def create
    required = [:jsonld, :artifact, :version, :file]
    if required.all? { |k| params.key? k }
      result = ExportGraphToDatabus.save_on_s3(jsonld: params[:jsonld], artifact: params[:artifact], version: params[:version], file:params[:file] )
      flash.now[:notice] = "Saving JSON-LD on S3: #{result}"
    else
      flash.now[:notice] = "Mising params. Required: #{required}"
    end
  end

  # POST /databus/artsdata?group=&artifact=&version=&downloadUrl=&downloadFile=
  # Create an entry on the Artsdata Databus
  def artsdata
    puts "starting artsdata webhook: #{webhook_messages_url}"
    group = params[:group]
    artifact = params[:artifact]
    download_url = params[:downloadUrl]
    download_file = params[:downloadFile]
    version = params[:version]
    data = ExportGraphToDatabus.add_to_databus(group: group, artifact: artifact, download_url: download_url, download_file: download_file, version: version, report_callback_url: webhook_messages_url(artifact: artifact, format: :json))
    if data.code[0] == 2
      render json: { message: data }.to_json
    else
      render json: { error: data }.to_json
    end
  end
end
