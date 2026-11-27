xpath=//div[@class='page-top__taglist-wrapper js-scrollfire scrollfire-fade-up']
;ruby=[$array.map{|e| e.squish}]
;xpath=//span[@class='information__price-type']
;ruby=[$array]
;xpath_sanitize=//span[contains(@class, 'information__price')]//a[contains(@class,'primary-button')]/@href
;ruby=flags = $array.first
ticket_types = flags.drop(1)
urls = $array[1..]
status_based_on_flags = if flags.flatten.include?("Complet")
  "http://schema.org/SoldOut"
elsif flags.flatten.include?("Annulé")
  "http://schema.org/Discontinued"
elsif flags.flatten.include?("Il reste quelques billets!")
  "http://schema.org/LimitedAvailability"
elsif flags.flatten.any? { |flag| flag.match?(/^(5 à 11 ans|Gratuit)$/) }
  "http://schema.org/InStock"
else
  "http://schema.org/InStock"
end
availability_statuses = []
ticket_types.each_with_index do |_, index|
  availability_statuses << (urls[index].to_s.empty? ? "http://schema.org/SoldOut" : status_based_on_flags)
end
availability_statuses
