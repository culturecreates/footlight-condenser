module CcKgHelper

  def cc_kg_query  q, cache_key
    @cckg_cache = {} if !defined? @cckg_cache
    if !@cckg_cache[cache_key]
      data = HTTParty.post("http://rdf.ontotext.com/4045483734/cc/repositories/webPages",
        body: {'query' => q},
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded',
                  'Accept' => 'application/json',
                  'Authorization' => 'Basic czRkYWxsZGdnaDgxOjUwZjVnMXQ3OTI4OXFqdg=='} )

      if data.response.code[0] == '2'
        result = JSON.parse(data.body)["results"]["bindings"]
        @cckg_cache[cache_key] = result
      else
        result =  {error: data.response.inspect}
      end
    else
      result = @cckg_cache[cache_key]
    end
    return result
  end
end
