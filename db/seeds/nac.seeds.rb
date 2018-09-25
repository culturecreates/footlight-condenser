# rails db:seed:single SEED=nac

@site = Website.create!(seedurl: "nac-cna-ca")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["https://nac-cna.ca/en/event/18816","adr:nac-cna-ca_18816-2018", "en"],
  ["https://nac-cna.ca/fr/event/18816","adr:nac-cna-ca_18816-2018", "fr"],
  ["https://nac-cna.ca/en/event/18727","adr:nac-cna-ca_18727-2018", "en"],
  ["https://nac-cna.ca/fr/event/18727","adr:nac-cna-ca_18727-2018", "fr"],
  ["https://nac-cna.ca/en/event/18730","adr:nac-cna-ca_18730-2018", "en"],
  ["https://nac-cna.ca/fr/event/18730","adr:nac-cna-ca_18730-2018", "fr"],
  ["https://nac-cna.ca/en/event/18654","adr:nac-cna-ca_18654-2018", "en"],
  ["https://nac-cna.ca/fr/event/18654","adr:nac-cna-ca_18654-2018", "fr"],
  ["https://nac-cna.ca/en/event/18657","adr:nac-cna-ca_18657-2018", "en"],
  ["https://nac-cna.ca/fr/event/18657","adr:nac-cna-ca_18657-2018", "fr"],
  ["https://nac-cna.ca/en/event/18653","adr:nac-cna-ca_18653-2018", "en"],
  ["https://nac-cna.ca/fr/event/18653","adr:nac-cna-ca_18653-2018", "fr"],
  ["https://nac-cna.ca/en/event/18658","adr:nac-cna-ca_18658-2018", "en"],
  ["https://nac-cna.ca/fr/event/18658","adr:nac-cna-ca_18658-2018", "fr"],
  ["https://nac-cna.ca/en/event/18652","adr:nac-cna-ca_18652-2018", "en"],
  ["https://nac-cna.ca/fr/event/18652","adr:nac-cna-ca_18652-2018", "fr"],
  ["https://nac-cna.ca/en/event/18663","adr:nac-cna-ca_18663-2018", "en"],
  ["https://nac-cna.ca/fr/event/18663","adr:nac-cna-ca_18663-2018", "fr"],
  ["https://nac-cna.ca/en/event/19445","adr:nac-cna-ca_19445-2018", "en"],
  ["https://nac-cna.ca/fr/event/19445","adr:nac-cna-ca_19445-2018", "fr"],
  ["https://nac-cna.ca/en/event/20041","adr:nac-cna-ca_20041-2018", "en"],
  ["https://nac-cna.ca/en/event/20049","adr:nac-cna-ca_20049-2018", "en"],
  ["https://nac-cna.ca/en/event/19036","adr:nac-cna-ca_19036-2018", "en"],
  ["https://nac-cna.ca/en/event/19035","adr:nac-cna-ca_19035-2018", "en"],
  ["https://nac-cna.ca/en/event/19034","adr:nac-cna-ca_19034-2018", "en"],
  ["https://nac-cna.ca/en/event/19033","adr:nac-cna-ca_19033-2018", "en"],
  ["https://nac-cna.ca/en/event/20035","adr:nac-cna-ca_20035-2018", "en"],
  ["https://nac-cna.ca/en/event/18651","adr:nac-cna-ca_18651-2018", "en"],
  ["https://nac-cna.ca/en/event/19297","adr:nac-cna-ca_19297-2018", "en"],
  ["https://nac-cna.ca/en/event/18633","adr:nac-cna-ca_18633-2018", "en"],
  ["https://nac-cna.ca/fr/event/20041","adr:nac-cna-ca_20041-2018", "fr"],
  ["https://nac-cna.ca/fr/event/20049","adr:nac-cna-ca_20049-2018", "fr"],
  ["https://nac-cna.ca/fr/event/19036","adr:nac-cna-ca_19036-2018", "fr"],
  ["https://nac-cna.ca/fr/event/19035","adr:nac-cna-ca_19035-2018", "fr"],
  ["https://nac-cna.ca/fr/event/19034","adr:nac-cna-ca_19034-2018", "fr"],
  ["https://nac-cna.ca/fr/event/19033","adr:nac-cna-ca_19033-2018", "fr"],
  ["https://nac-cna.ca/fr/event/20035","adr:nac-cna-ca_20035-2018", "fr"],
  ["https://nac-cna.ca/fr/event/18651","adr:nac-cna-ca_18651-2018", "fr"],
  ["https://nac-cna.ca/fr/event/19297","adr:nac-cna-ca_19297-2018", "fr"],
  ["https://nac-cna.ca/fr/event/18633","adr:nac-cna-ca_18633-2018", "fr"]
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


create_source("Title",{selected: false, algo: "xpath=//title", languages: ["en","fr"]})
create_source("Title",{selected: false, algo: "xpath=//div[@class='title large-12 xlarge-8 columns'];ruby=$array.map {|s| s.squish}", languages: ["en","fr"]})
create_source("Title",{algo: "xpath=//script[@type='application/ld+json'];ruby=CGI::unescapeHTML(CGI::unescapeHTML(JSON.parse($array.first.squish).first['name_en']))", languages: ["en"]})
create_source("Title",{algo: "xpath=//script[@type='application/ld+json'];ruby=CGI::unescapeHTML(CGI::unescapeHTML(JSON.parse($array.first.squish).first['name_fr']))", languages: ["fr"]})
create_source("Description",{selected: false, algo: "xpath=//div[@class='event_main_copy'];ruby=$array.first.squish.gsub(/ Learn more ›/,'')", languages: ["en"]})
create_source("Description",{selected: false, algo: "xpath=//div[@class='event_main_copy'];ruby=$array.first.squish.gsub(/ En savoir plus ›/,'')", languages: ["fr"]})
create_source("Description",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(JSON.parse($array.first.squish).first['description_en'])", languages: ["en"]})
create_source("Description",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(JSON.parse($array.first.squish).first['description_fr'])", languages: ["fr"]})
create_source("Photo",{algo: "xpath=//script[@type='application/ld+json'];ruby=sanitize(JSON.parse($array.first.squish).first['image'])"})
create_source("Location",{algo: "xpath=//script[@type='application/ld+json'];ruby=JSON.parse($array.first.squish).select{|obj| obj['@type'] == 'Place'}.first['name'].split('*')"})
create_source("Start date",{algo: "xpath=//script[@type='application/ld+json'];ruby=JSON.parse($array.first.squish).map{ |e| e['startDate']}.select {|date| date != nil}.uniq"})
create_source("Organized by",{algo: "manual=National Arts Centre"})
create_source("Produced by",{algo: "xpath=//div[@class='event_main_copy'];ruby=$array.map {|s| s.squish}.join(', ').truncate_words(20).split('*')"})
create_source("Performed by",{algo: "xpath=//section[@id='event_artist_credits']//li;ruby=$array.map {|p| p.squish}.join(', ').truncate_words(20).split('*')"})
create_source("Tickets link",{algo: "xpath=//div[@class='event_sales_original'];ruby=$array.first.squish.truncate_words(4)", languages: ["en","fr"]})
create_source("Webpage link",{algo: "ruby=$url", languages: ["en","fr"]})
create_source("Duration", {algo: "xpath=//p[@class='duration']"})


create_source("Event type", {algo: "manual=Live performance"})
create_source("Name", {rdfs_class_id: 4, algo: "manual=Live performance"})
