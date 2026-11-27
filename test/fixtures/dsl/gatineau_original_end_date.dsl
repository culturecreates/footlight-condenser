xpath=//div[@class='desktop']//div[@class='occurrences']//ul//li//span[@class='occurrence']//span[@class='date-heure']
;ruby=$array.map{ |str| str.match?(/[Dd]u.*au|de .* à/) ? str.gsub(/.* au (.*)/,'\1').gsub(/,? de [0-9]*:[0-9]* à/, ',') : ""}
;ruby=[$array]
;if_xpath=//div[@class='desktop']//span[@class='addeventatc']//span[contains(@class,'end')]
;ruby=$array.length > 1 ? $array.drop(1).map{|d| d.split(" ").first}.map{|dt| Date.strptime(dt, '%m-%d-%Y').to_s} : $array.first.flatten
