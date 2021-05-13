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
      if result.contents
        @contents = result.contents
      end
    rescue Aws::Sigv4::Errors::MissingCredentialsError => credentials_error
      flash.now[:notice] = credentials_error.message
    end
  end

  # POST /databus?jsonld=&artifact=&version=&file=
  # Save JSON-LD on S3
  def create
    required = [:jsonld, :artifact, :version, :file]
    if required.all? { |k| params.key? k }
      result = save_on_s3(jsonld: params[:jsonld], artifact: params[:artifact], version: params[:version], file:params[:file] )
      flash.now[:notice] = "Request was saved successfully. #{result}"
    else
      flash.now[:notice] = "Mising params. Required: #{required}"
    end
  end

  # POST /databus/artsdata?group=&artifact=&version=&downloadUrl=&downloadFile=\
  # Create an entry on the Artsdata Databus
  def artsdata
    group = params[:group]
    artifact = params[:artifact]
    download_url = params[:downloadUrl]
    download_file = params[:downloadFile]
    version = params[:version]
    data = add_to_databus(group: group, artifact: artifact, download_url: download_url, download_file: download_file, version: version)
    if data.code[0] == 2
      render json: { message: data }.to_json
    else
      render json: { error: data }.to_json
    end
  end

  # Save a JSON-LD on S3
  def save_on_s3(jsonld:, artifact:, version:, file:)
    bucket = "data.culturecreates.com"

    begin
      client = Aws::S3::Client.new(region: "ca-central-1", access_key_id: ENV["ACCESS_KEY_ID"], secret_access_key: ENV["SECRET_ACCESS_KEY"])
      client.put_object(
        bucket: bucket,
        key: "databus/culture-creates/footlight/#{artifact}/#{version}/#{file}", 
        body: jsonld
      )
    rescue Aws::Sigv4::Errors::MissingCredentialsError => credentials_error
      credentials_error
    end
  end

  def add_to_databus(group:, artifact:, download_url:, download_file:, version:)
    artsdata_url = 'http://api.artsdata.ca/databus'
    publisher = 'https://graph.culturecreates.com/id/footlight'
    report_callback_url = 'https://webhook.site/a4b17b13-ba49-4456-b010-1776fec399ad'
    # To view callbacks https://webhook.site/#!/a4b17b13-ba49-4456-b010-1776fec399ad

    data = HTTParty.post(artsdata_url,
      query: {
        publisher: publisher,
        group: group,
        artifact: artifact,
        version: version,
        downloadUrl: download_url,
        downloadFile: download_file,
        reportCallbackUrl: report_callback_url
      } # ,
      #headers: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
      #          'Accept' => 'application/json'},
      # timeout: 4
    )
  end
end
