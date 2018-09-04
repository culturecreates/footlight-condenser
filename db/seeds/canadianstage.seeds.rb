# rails db:seed:single SEED=dansedanse

@site = Website.create!(seedurl: "canadianstage-com")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["https://www.canadianstage.com/online/shakespeare","adr:canadianstage-com_shakespeare_2018", "en"],
  ["https://www.canadianstage.com/online/grand-finale","adr:canadianstage-com_grand-finale_2018", "en"],
  ["https://www.canadianstage.com/online/children","adr:canadianstage-com_children_2018","en"]
]


pages.each do |page|
  Webpage.create!(url: page[0], rdf_uri: page[1], language: page[2], website: @site, rdfs_class: RdfsClass.where(name: "Event").first)
end


def self.create_source(label, options={})
  options[:algo]      ||= ''
  options[:next_algo] ||= ''
  options[:selected]  ||= true
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
create_source("Title",{algo: "xpath=//title;ruby=$array[0] + ' | Canadian Stage'",languages: ["en"], selected: false})
create_source("Description",{algo: "xpath=//div[@id='overview']//div[@class='mol-md-6 mol-sm-12'];ruby=$array.first.squish.gsub(/Subscribe *\+ *Save/,'')", languages: ["en"]})
create_source("Description",{algo: "xpath=//div[@class='middleTitle']//h2;ruby=$array.first.squish.downcase.upcase_first", languages: ["en"], selected: false})
create_source("Photo",{algo: 'xpath=//div[@id="cs-carousel-image"]//img/@src;ruby="https://canadianstage.com#{$array.first}"'})
create_source("Photo",{selected: false, algo: 'xpath=//div[@id="cs-carousel-image"]//img/@src;ruby="https://canadianstage.com#{$array.second}"'})
create_source("Location",{algo: "manual=Enter the location"})
create_source("Start date")
create_source("Organized by",{algo: "manual=Enter the organization that organized this event"})
create_source("Produced by",{algo: "manual=Enter the organization that produced this event"})
create_source("Performed by",{algo: "manual=Enter the organization that performed this event"})
create_source("Tickets link",{algo: "ruby=$url", languages: ["en"]})
create_source("Webpage link",{algo: "ruby=$url", languages: ["en"]})
