module CcKgHelper

  def cc_kg_query  q, cache_key
    #If the KG server is down then return an error that will abort the update of the current property.
    result = {}
    @cckg_cache = {} if !defined? @cckg_cache
    if !@cckg_cache[cache_key]
      begin
        data = HTTParty.post("http://db.artsdata.ca/repositories/artsdata",
          body: {'query' => q},
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
                    'Accept' => 'application/json'},
         timeout: 4 )
        if data.response.code[0] == '2'
            result[:data] = JSON.parse(data.body)["results"]["bindings"]
            @cckg_cache[cache_key] = result
        else
          result =  {error: data.response.message, response: data}
        end
      rescue => e
        result = {error: "RESCUE while searching in Knowledge Graph: #{e.inspect} "}
      end
    else
      result = @cckg_cache[cache_key]
    end
    return result
  end

end
