# rails db:seed:single SEED=nac

@site = Website.create!(seedurl: "nac-cna-ca")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["https://nac-cna.ca/en/event/18816","adr:nac-cna-ca_silence-2018", "en"],
  ["https://nac-cna.ca/fr/event/18816","adr:nac-cna-ca_silence-2018", "fr"],
  ["https://nac-cna.ca/en/event/18727","adr:nac-cna-ca_beethoven-ninth-2018", "en"],
  ["https://nac-cna.ca/fr/event/18727","adr:nac-cna-ca_beethoven-ninth-2018", "fr"],
  ["https://nac-cna.ca/en/event/18730","adr:nac-cna-ca_handel-2018", "en"],
  ["https://nac-cna.ca/fr/event/18730","adr:nac-cna-ca_handel-2018", "fr"],
  ["https://nac-cna.ca/en/event/18654","adr:nac-cna-ca_alonzo-king-lines-ballet-2018", "en"],
  ["https://nac-cna.ca/fr/event/18654","adr:nac-cna-ca_alonzo-king-lines-ballet-2018", "fr"],
  ["https://nac-cna.ca/en/event/18657","adr:nac-cna-ca_alberta-ballet-2018", "en"],
  ["https://nac-cna.ca/fr/event/18657","adr:nac-cna-ca_alberta-ballet-2018", "fr"],
  ["https://nac-cna.ca/en/event/18653","adr:nac-cna-ca_les-grands-ballets-2018", "en"],
  ["https://nac-cna.ca/fr/event/18653","adr:nac-cna-ca_les-grands-ballets-2018", "fr"],
  ["https://nac-cna.ca/en/event/18658","adr:nac-cna-ca_akram-khan-company-2018", "en"],
  ["https://nac-cna.ca/fr/event/18658","adr:nac-cna-ca_akram-khan-company-2018", "fr"],
  ["https://nac-cna.ca/en/event/18652","adr:nac-cna-ca_le-ballet-national-2018", "en"],
  ["https://nac-cna.ca/fr/event/18652","adr:nac-cna-ca_le-ballet-national-2018", "fr"],
  ["https://nac-cna.ca/en/event/18663","adr:nac-cna-ca_fortier-2018", "en"],
  ["https://nac-cna.ca/fr/event/18663","adr:nac-cna-ca_fortier-2018", "fr"],
  ["https://nac-cna.ca/en/event/19445","adr:nac-cna-ca_tom-wilson-lynn-miles-2018", "en"],
  ["https://nac-cna.ca/fr/event/19445","adr:nac-cna-ca_tom-wilson-lynn-miles-2018", "fr"]
]


pages.each do |page|
  Webpage.create!(url: page[0], rdf_uri: page[1], language: page[2], website: @site, rdfs_class: RdfsClass.where(name: "Event").first)
end

Webpage.create!(url: 'http://placeholder.com', rdf_uri: "adr:category-event-type_live-performance", language: '', website: @site, rdfs_class: RdfsClass.where(name: "Category").first)


def self.create_source(label, options={})
  options[:algo]      ||= ''
  options[:next_algo] ||= ''
  options[:selected] = true if options[:selected].nil?
  options[:languages] ||= [""]
  options[:rdfs_class_id] ||= 1  #Event class

  options[:languages].each do |lang|
    if !options[:next_algo].blank?
      s = Source.create!(language: lang, render_js: true, website: @site, property: Property.where(label: label).first, algorithm_value: options[:next_algo], selected: options[:selected])
      Source.create!(language: lang, next_step: s.id, website: @site, property: Property.where(label: label).first, algorithm_value: options[:algo], selected: options[:selected])
    else
      Source.create!(language: lang, website: @site, property: Property.where(label: label, rdfs_class_id: options[:rdfs_class_id]).first, algorithm_value: options[:algo], selected: options[:selected])
    end
  end
end


create_source("Title",{algo: "xpath=//title", languages: ["en","fr"]})
create_source("Title",{algo: "xpath=//div[@class='title large-12 xlarge-8 columns'];ruby=$array.map {|s| s.squish}", selected: false, languages: ["en","fr"]})
create_source("Title",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(CGI::unescapeHTML(JSON.parse($array.first).first['name_en'])) + ' | National Arts Centre'", selected: false, languages: ["en"]})
create_source("Title",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(CGI::unescapeHTML(JSON.parse($array.first).first['name_fr'])) + ' | Centre national des Arts'", selected: false, languages: ["fr"]})
create_source("Description",{selected: false, algo: "xpath=//div[@class='event_main_copy'];ruby=$array.first.squish.gsub(/ Learn more ›/,'')", languages: ["en"]})
create_source("Description",{selected: false, algo: "xpath=//div[@class='event_main_copy'];ruby=$array.first.squish.gsub(/ En savoir plus ›/,'')", languages: ["fr"]})
create_source("Description",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(JSON.parse($array.first).first['description_en'])", languages: ["en"]})
create_source("Description",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(JSON.parse($array.first).first['description_fr'])", languages: ["fr"]})
create_source("Photo",{algo: "xpath=//meta[@name='thumbnail']/@content"})
create_source("Location",{algo: "xpath=//script[@type='application/ld+json'];ruby=JSON.parse($array.first).second['name'].split('*')"})
create_source("Start date",{algo: "xpath=//script[@type='application/ld+json'];ruby=JSON.parse($array.first).map { |e| e['startDate'] }.uniq"})
create_source("Organized by",{algo: "manual=National Arts Centre"})
create_source("Produced by",{algo: "xpath=//div[@class='event_main_copy'];ruby=$array.map {|s| s.squish}.join(', ').truncate_words(10).split('*')"})
create_source("Performed by",{algo: "xpath=//section[@id='event_artist_credits']//li;ruby=$array.map {|p| p.squish}.join(', ').split('*')"})
create_source("Tickets link",{algo: "xpath=//div[@class='event_sales_original'];ruby=$array.first.squish.truncate_words(4)", languages: ["en","fr"]})
create_source("Webpage link",{algo: "ruby=$url", languages: ["en","fr"]})
create_source("Duration", {algo: "xpath=//p[@class='duration']"})


create_source("Event type", {algo: "manual=Live performance"})
create_source("Name", {rdfs_class_id: 4, algo: "manual=Live performance"})
