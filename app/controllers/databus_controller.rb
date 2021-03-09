class DatabusController < ApplicationController
  # GET /databus
  def index
    client = Aws::S3::Client.new(region: "ca-central-1", access_key_id: ENV["ACCESS_KEY_ID"], secret_access_key: ENV["SECRET_ACCESS_KEY"])
    result = client.list_objects(
      bucket: "data.culturecreates.com", 
      max_keys: 20, 
      prefix: 'databus/culture-creates/footlight/'
    )
    if result.contents
      @contents = result.contents
    end
  end

  # POST /databus?jsonld=&artifact=&version=
  def create
    required = [:jsonld, :artifact,  :version, :file]
    if required.all? { |k| params.key? k }
      result = save_on_s3(jsonld: params[:jsonld], artifact: params[:artifact], version: params[:version], file:params[:file] )
      flash.now[:notice] = "Request was saved successfully. #{result}"
    else
      flash.now[:notice] = "Mising params. Required: #{required}"
    end
  end

  # POST /databus/artsdata?group=&artifact=&version=&downloadURL=&downloadFile=
  def artsdata
      artsdata_url = 'http://api.artsdata.ca/databus'
      publisher = 'https://graph.culturecreates.com/id/footlight'
      reportCallbackUrl = 'https://webhook.site/a4b17b13-ba49-4456-b010-1776fec399ad'
       # To view callbacks https://webhook.site/#!/a4b17b13-ba49-4456-b010-1776fec399ad
      group = params[:group]
      artifact = params[:artifact]
      downloadUrl = params[:downloadUrl]
      downloadFile = params[:downloadFile]
      version = params[:version]

      puts "downloadFile: #{downloadFile}"

      data = HTTParty.post(artsdata_url,
        query: {
          publisher: publisher,
          group: group,
          artifact: artifact,
          version: version,
          downloadUrl: downloadUrl,
          downloadFile: downloadFile,
          reportCallbackUrl: reportCallbackUrl
        },
        #headers: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
        #          'Accept' => 'application/json'},
        # timeout: 4 
      )
      puts "data: #{data}"
      render json: { message: data }.to_json




  end

  def save_on_s3(jsonld:, artifact:, version:, file:)
    client = Aws::S3::Client.new(region: "ca-central-1", access_key_id: ENV["ACCESS_KEY_ID"], secret_access_key: ENV["SECRET_ACCESS_KEY"])
    bucket = "data.culturecreates.com"
    client.put_object(
      bucket: bucket,
      key: "databus/culture-creates/footlight/#{artifact}/#{version}/#{file}", 
      body: jsonld
    )
  end
end
