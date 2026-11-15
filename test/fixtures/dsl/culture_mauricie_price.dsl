xpath=//ul[@class='performances']//a/@href
;ruby=[$url, $array]                                                             # Keep for later
;if_xpath=//body/@data-reference | //li//li[contains(@class,'performances-sub-item')]/@data-tpos-event
;url='https://lepointdevente.com/plugins/rates/' + $array.last                   # URL to json if data-reference exists
;json=$json.dig('rates')                                                         # Order json if $array.last is not nil
;url=$array.first                                                                # Back to original URL (prepare for 2nd case)
;ruby=
# Find the tickets array anywhere in $array (work backward to grab the most recent)
tickets = nil
$array.reverse.each do |el|
  if el.is_a?(Array) && el.any? { |x| x.is_a?(Hash) && x.key?('price') }
    tickets = el
    break
  end
end

if tickets
  # Return numeric prices, skip nils (e.g., "Courtoisie" with no price)
  tickets
    .select { |x| x.is_a?(Hash) && x.key?('price') && !x['price'].nil? }
    .map    { |x| x['price'].to_f.round(2) }
elsif (h = $array.reverse.find { |el| el.is_a?(Hash) && el.key?('price') })
  p = h['price']
  p.nil? ? [] : [p.to_f.round(2)]
else
  []
end
