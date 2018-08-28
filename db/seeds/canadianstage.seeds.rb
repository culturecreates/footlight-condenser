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


def self.create_source( label, algo = "", next_algo = "", selected = true, languages = [""])
  languages.each do |lang|
    if !next_algo.blank?
      s = Source.create!(language: lang, render_js: true, website: @site, property: Property.where(label: label).first, algorithm_value:next_algo, selected:selected)
      Source.create!(language: lang, next_step: s.id, website: @site, property: Property.where(label: label).first, algorithm_value:algo, selected:selected)
    else
      Source.create!(language: lang, website: @site, property: Property.where(label: label).first, algorithm_value:algo, selected:selected)
    end
  end
end

create_source("Title","","",true,["en"])
create_source("Title","","",false,["en"])
create_source("Description","","",true,["en"])
create_source("Description","","",false,["en"])
create_source("Photo",'xpath=//div[@id="cs-carousel-image"]//img/@src,ruby="https://canadianstage.com#{$array.first}"')
create_source("Photo",'xpath=//div[@id="cs-carousel-image"]//img/@src,ruby="https://canadianstage.com#{$array.second}"',"",false)
create_source("Location")
create_source("Start date")
create_source("Organized by")
create_source("Produced by","manual=Enter the organization that produced this event")
create_source("Performed by","manual=Enter the organization that performed this event")
create_source("Tickets link","","",true,["en"])
create_source("Webpage link","","",true,["en"])
