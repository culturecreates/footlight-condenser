module BatchJobsHelper

    HUGINN_SECRET = "footlightsecret"
    HUGINN_BASE_URL = "https://culture-huginn.herokuapp.com/users/1/web_requests/"


    def huginn_webhook  body_label, body_data, huginn_hook_id
        result = {}
       
          begin
            huginn_url = "#{HUGINN_BASE_URL}/#{huginn_hook_id}/#{HUGINN_SECRET}"
            data = HTTParty.post(huginn_url,
              body: {body_label => body_data},
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
