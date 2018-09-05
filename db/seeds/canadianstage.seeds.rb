# rails db:seed:single SEED=dansedanse

@site = Website.create!(seedurl: "canadianstage-com")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["https://www.canadianstage.com/online/shakespeare","adr:canadianstage-com_shakespeare_18-19-season", "en"],
  ["https://www.canadianstage.com/online/children","adr:canadianstage-com_children_18-19-season","en"],
  ["https://canadianstage.com/online/xenos","adr:canadianstage-com_xenos_18-19-season","en"],
  ["https://canadianstage.com/online/trace","adr:canadianstage-com_trace_18-19-season","en"],
  ["https://www.canadianstage.com/online/grand-finale","adr:canadianstage-com_grand-finale_18-19-season", "en"],
  ["https://canadianstage.com/online/every-brilliant-thing","adr:canadianstage-com_every-brilliant-thing_18-19-season","en"],
  ["https://canadianstage.com/online/tartuffe","adr:canadianstage-com_tartuffe_18-19-season","en"],
  ["https://canadianstage.com/online/prince-hamlet","adr:canadianstage-com_prince-hamlet_18-19-season","en"],
  ["https://canadianstage.com/online/who-we-are","adr:canadianstage-com_who-we-are_18-19-season","en"],
  ["https://canadianstage.com/online/revisor","adr:canadianstage-com_revisor_18-19-season","en"],
  ["https://canadianstage.com/online/unsafe","adr:canadianstage-com_unsafe_18-19-season","en"],
  ["https://canadianstage.com/online/bigre","adr:canadianstage-com_bigre_18-19-season","en"],
  ["https://canadianstage.com/online/887","adr:canadianstage-com_887_18-19-season","en"],
  ["https://canadianstage.com/online/moon","adr:canadianstage-com_moon_18-19-season","en"],
  ["https://canadianstage.com/online/by-heart","adr:canadianstage-com_by-heart_18-19-season","en"],
  ["https://canadianstage.com/online/full-ligh","adr:canadianstage-com_full-ligh_18-19-season","en"]
]


pages.each do |page|
  Webpage.create!(url: page[0], rdf_uri: page[1], language: page[2], website: @site, rdfs_class: RdfsClass.where(name: "Event").first)
end


def self.create_source(label, options={})
  options[:algo]      ||= ''
  options[:next_algo] ||= ''
  options[:selected] = true if options[:selected].nil?
  options[:languages] ||= [""]

  options[:languages].each do |lang|
    if !options[:next_algo].blank?
      s = Source.create!(language: lang, render_js: true, website: @site, property: Property.where(label: label).first, algorithm_value: options[:next_algo], selected: options[:selected])
      Source.create!(language: lang, next_step: s.id, website: @site, property: Property.where(label: label).first, algorithm_value: options[:algo], selected: options[:selected])
    else
      Source.create!(language: lang, website: @site, property: Property.where(label: label).first, algorithm_value: options[:algo], selected: options[:selected])
    end
  end
end

create_source("Title",{algo: "xpath=//title", languages: ["en"]})
create_source("Title",{selected: false, algo: "xpath=//title;ruby=$array[0] + ' | Canadian Stage'",languages: ["en"]})
create_source("Description",{algo: "xpath=//div[@id='overview']//div[@class='mol-md-6 mol-sm-12'];ruby=$array.first.squish.gsub(/Subscribe *\+ *Save/,'')", languages: ["en"]})
create_source("Description",{selected: false, algo: "xpath=//div[@class='middleTitle']//h2;ruby=$array.first.squish.downcase.upcase_first", languages: ["en"]})
create_source("Photo",{algo: 'xpath=//div[@id="cs-carousel-image"]//img/@src;ruby="https://canadianstage.com#{$array.first}"'})
create_source("Photo",{selected: false, algo: 'xpath=//div[@id="cs-carousel-image"]//img/@src;ruby="https://canadianstage.com#{$array.second}"'})
create_source("Photo",{selected: false, algo: 'xpath=//div[@id="cs-carousel-image"]//img/@src;ruby="https://canadianstage.com#{$array[2]}"'})
create_source("Location",{algo: "xpath=//div[@id='overview']//ul//li;ruby=$array.select {|item| item.include? 'Location'}.map {|item| item.squish.sub(/Location: /,'')}"})
create_source("Start date",{algo: "xpath=//div[@class='item-start-date']/span[@class='start-date']"})
create_source("Organized by",{algo: "manual=Enter the organization that organized this event"})
create_source("Produced by",{algo: "manual=Enter the organization that produced this event"})
create_source("Performed by",{algo: "manual=Enter the organization that performed this event"})
create_source("Tickets link",{algo: "ruby=$url", languages: ["en"]})
create_source("Webpage link",{algo: "ruby=$url", languages: ["en"]})
create_source("Duration", {algo: "xpath=//div[@id='overview']//ul//li[2];ruby=$array.select {|item| item.include? 'Run Time'}.map {|item| item.squish.sub(/Run Time:(.*)\(+.*/,'\1').strip}"})
