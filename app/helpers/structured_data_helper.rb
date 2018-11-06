module StructuredDataHelper
  include CcKgHelper

  def get_kg_place place_uri

    place_uri = "<#{place_uri}>" if place_uri[0..3] == "http"

    q = "PREFIX  adr:  <http://corpo.culturecreates.com/#>  \
        select ?pred ?obj where {    \
         #{place_uri} ?a ?b   .  \
         ?b  a  <http://schema.org/PostalAddress> .   \
         ?b  ?pred ?obj .    \
         }"
    result = cc_kg_query(q, place_uri)

    if result.class == Array
      place = {}
      result.each do |statement|
        place[statement["pred"]["value"].to_s.split('/').last] =  statement["obj"]["value"]
      end
    else
      place = {:error => result[:error]}
    end
    return place
  end

  def make_into_array str
    if str[0] != "[" 
      array = [] << str
    else
      array = JSON.parse(str)
    end
    return array
  end

end
