class DatabusController < ApplicationController
  def index

    client = Aws::S3::Client.new(region: "ca-central-1", access_key_id: ENV["ACCESS_KEY_ID"], secret_access_key: ENV["SECRET_ACCESS_KEY"])
    @result = client.list_objects(
      bucket: "data.culturecreates.com", 
      max_keys: 20, 
      prefix: 'databus/culture-creates/footlight/'
    )
    if @result.contents
      @contents = @result.contents
    end

  end

  # POST /databus?jsonld=&artifact=&version=
  def create
    required = [:jsonld, :artifact,  :version, :file]
    if required.all? { |k| params.key? k }
      client = Aws::S3::Client.new(region: "ca-central-1")
      bucket = "data.culturecreates.com"
      @result= client.put_object(
        bucket: bucket,
        key: "databus/culture-creates/footlight/#{params[:artifact]}/#{params[:version]}/#{params[:file]}", 
        body: params[:jsonld]
      )
      render json: { code: 201, message: "ok"}, status: 201, callback: params['callback'] 
    else
      render json: { code: 400, message: 'missing params' }, status: 400, callback: params['callback'] 
    end  
  
  
  end
end
