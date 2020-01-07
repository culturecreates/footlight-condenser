module ListsHelper

    def huginn_webhook  webpages
        result = {}
       
          begin
            huginn_url = "https://culture-huginn.herokuapp.com/users/1/web_requests/249/footlightsecret"
            data = HTTParty.post(huginn_url,
              body: {'webpages' => webpages},
              headers: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
                        'Accept' => 'application/json'},
             timeout: 4 )
            if data.response.code[0] == '2'
                result[:data] = data.body
            else
              result =  {error: data.response.code, response: data}
            end
          rescue => e
            result = {error: "RESCUE while calling Huginn webhook: #{e.inspect} "}
          end
         
        return result
    end

end
