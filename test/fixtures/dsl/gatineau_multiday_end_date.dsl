if_xpath=//div[@class='desktop']//div[@class='occurrences']//ul//li//span[@class='occurrence']//span[@class='date-heure'][starts-with(normalize-space(.),'Du ') and contains(normalize-space(.),' au ')]
;ruby=
# Extract the ending calendar date, without its time
months = %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre]
dates = $array.filter_map do |text|
  parts = text.split(/\s+au\s+/i, 2)
  pattern = /(\d{1,2})\s+(#{months.join('|')})\s+(\d{4})/i
  a, b = parts.map do |part|
    m = part.match(pattern)
    raise "Invalid date interval: #{text}" unless m
    Date.new(m[3].to_i, months.index(m[2].downcase) + 1, m[1].to_i)
  end
  raise "End before start: #{text}" if b < a
  b.iso8601 if b > a
end.uniq
raise "Multiple End Dates: #{dates.inspect}" if dates.size > 1
dates
