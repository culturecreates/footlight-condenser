# rails db:seed:single SEED=dansedanse

@site = Website.create!(seedurl: "hector-charland-com")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["https://hector-charland.com/programmation/grandes-dames/","adr:hector-charland-com_grandes-dames", "fr"],
  ["https://hector-charland.com/programmation/vraiment-doucement/","adr:hector-charland-com_vraiment-doucement", "fr"],
  ["https://hector-charland.com/programmation/casse-noisette-3/","adr:hector-charland-com_casse-noisette-3", "fr"],
  ["https://hector-charland.com/programmation/mecaniques-nocturnes/","adr:hector-charland-com_mecaniques-nocturnes", "fr"]
]


pages.each do |page|
  Webpage.create!(url: page[0], rdf_uri: page[1], language: page[2], website: @site, rdfs_class: RdfsClass.where(name: "Event").first)
end

Webpage.create!(url: 'http://placeholder.com', rdf_uri: "adr:category-event-type_live-performance", language: 'fr', website: @site, rdfs_class: RdfsClass.where(name: "Category").first)


def self.create_source(label, options={})
  options[:algo]      ||= ''
  options[:next_algo] ||= ''
  options[:selected] = true if options[:selected].nil?
  options[:languages] ||= [""]
  options[:rdfs_class_id] ||= 1  #Event class

  options[:languages].each do |lang|
    if !options[:next_algo].blank?
      s = Source.create!(language: lang, render_js: true, website: @site, property: Property.where(label: label).first, algorithm_value: options[:next_algo], selected: options[:selected])
      Source.create!(language: lang, website: @site, property: Property.where(label: label).first, algorithm_value: options[:algo], selected: options[:selected])
    else
      Source.create!(language: lang, website: @site, property: Property.where(label: label, rdfs_class_id: options[:rdfs_class_id]).first, algorithm_value: options[:algo], selected: options[:selected])
    end
  end
end


create_source("Title",{algo: "xpath=//title", languages: ["fr"]})
create_source("Description",{languages: ["fr"], algo: "xpath=//meta[@property='og:description']/@content"})
create_source("Description",{selected: false, languages: ["fr"], algo: "xpath=//section[@id='fiche_txt'];ruby=$array.map {|t| t.squish}"})
create_source("Photo",{languages: ["fr"], algo: "xpath=//meta[@property='og:image']/@content;ruby=$array.select {|i| !(i.include? 'share.jpg')}"})
create_source("Location",{languages: ["fr"], algo: "xpath=(//td[@class='cell_salle'])[1];ruby=$array.map {|t| t.squish}	"})
create_source("Start date",{languages: ["fr"], algo: "xpath=//div[@class='show_date']"})
create_source("Organized by",{languages: ["fr"], algo: "manual=Théâtre Hector-Charland"})
create_source("Produced by",{languages: ["fr"], algo: "xpath=//section[@id='fiche_txt'];ruby=$array.map{|t| t.truncate_words(15)}.map {|t| t.squish}"})
create_source("Performed by",{languages: ["fr"], algo: "xpath=//section[@id='fiche_txt'];ruby=$array.map{|t| t.truncate_words(15)}.map {|t| t.squish}"})
create_source("Tickets link",{languages: ["fr"], algo: "xpath=//td[@class='cell_code']/a/@href;ruby=$array.map {|t| t.squish}"})
create_source("Webpage link",{algo: "ruby=$url", languages: ["fr"]})
create_source("Duration",{languages: ["fr"]})


create_source("Event type", {languages: ["fr"], algo: "manual=Live performance"})
create_source("Name", {languages: ["fr"], rdfs_class_id: 4, algo: "manual=Live performance"})
