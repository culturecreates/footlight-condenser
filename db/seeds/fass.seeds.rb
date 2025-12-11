# rails db:seed:single SEED=fass

@site = Website.create!(seedurl: "fass-ca")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["http://festivaldesarts.ca/en/performances/feature-presentations/romeo-et-juliette/","adr:festivaldesarts-ca_romeo-et-juliette","en"],
  ["http://festivaldesarts.ca/en/performances/feature-presentations/toronto-dance-theater/","adr:festivaldesarts-ca_toronto-dance-theater","en"],
  ["http://festivaldesarts.ca/en/performances/feature-presentations/orchestre-metropolitain/","adr:festivaldesarts-ca_orchestre-metropolitain","en"],
  ["http://festivaldesarts.ca/en/performances/feature-presentations/hubbard-street-dance-chicago/","adr:festivaldesarts-ca_hubbard-street-dance-chicago","en"],
  ["http://festivaldesarts.ca/en/performances/feature-presentations/yemen-blues/","adr:festivaldesarts-ca_yemen-blues","en"],
  ["http://festivaldesarts.ca/en/performances/feature-presentations/a-night-with-the-stars/","adr:festivaldesarts-ca_a-night-with-the-stars","en"],
  ["http://festivaldesarts.ca/en/performances/feature-presentations/guillaume-cote/","adr:festivaldesarts-ca_guillaume-cote","en"],
  ["http://festivaldesarts.ca/programmation/en-salle/romeo-et-juliette/","adr:festivaldesarts-ca_romeo-et-juliette","fr"],
  ["http://festivaldesarts.ca/programmation/en-salle/toronto-dance-theater/","adr:festivaldesarts-ca_toronto-dance-theater","fr"],
  ["http://festivaldesarts.ca/programmation/en-salle/orchestre-metropolitain/","adr:festivaldesarts-ca_orchestre-metropolitain","fr"],
  ["http://festivaldesarts.ca/programmation/en-salle/hubbard-street-dance-chicago/","adr:festivaldesarts-ca_hubbard-street-dance-chicago","fr"],
  ["http://festivaldesarts.ca/programmation/en-salle/yemen-blues/","adr:festivaldesarts-ca_yemen-blues","fr"],
  ["http://festivaldesarts.ca/programmation/en-salle/soiree-des-etoiles/","adr:festivaldesarts-ca_a-night-with-the-stars","fr"],
  ["http://festivaldesarts.ca/programmation/en-salle/guillaume-cote/","adr:festivaldesarts-ca_guillaume-cote","fr"]
]

pages.each do |page|
  Webpage.create!(url: page[0], rdf_uri: page[1], language: page[2], website: @site, rdfs_class: RdfsClass.where(name: "Event").first)
end

## Other types of Pages
Webpage.create!(url: "http://festivaldesarts.ca/en/visitors-infos/", website: @site, rdfs_class: RdfsClass.where(name: "Place").first, language: "en", rdf_uri: "adr:festivaldesarts-ca_visitors-infos")
Webpage.create!(url: "http://festivaldesarts.ca/infos-visiteurs/", website: @site, rdfs_class: RdfsClass.where(name: "Place").first, language: "fr", rdf_uri: "adr:festivaldesarts-ca_visitors-infos")
Webpage.create!(url: 'http://placeholder.com', rdf_uri: "adr:category-event-type_live-performance", language: '', website: @site, rdfs_class: RdfsClass.where(name: "Category").first)


def self.create_source(label, options={})
  options[:algo]      ||= ''
  options[:next_algo] ||= ''
  options[:selected] = true if options[:selected].nil?
  options[:languages] ||= [""]
  options[:rdfs_class_id] ||= 1  #Event class

  options[:languages].each do |lang|
    Rails.logger.debug label
    if options[:next_algo].present?
      s = Source.create!(language: lang, render_js: true, website: @site, property: Property.where(label: label).first, algorithm_value: options[:next_algo], selected: options[:selected])
      Source.create!(language: lang, website: @site, property: Property.where(label: label).first, algorithm_value: options[:algo], selected: options[:selected])
    else
      Source.create!(language: lang, website: @site, property: Property.where(label: label, rdfs_class_id: options[:rdfs_class_id]).first, algorithm_value: options[:algo], selected: options[:selected])
    end
  end
end


create_source "Title", {algo:"xpath=//meta[@property='og:title']/@content",selected: true,languages: ["en","fr"]}
create_source "Description", {algo:"xpath=//meta[@property='og:description']/@content",selected: false,languages: ["en","fr"] }
create_source "Description", {algo:"css=.fw-row :nth-child(1) .textblock-shortcode p:nth-child(1)",selected: true,languages: ["en","fr"] }
create_source "Webpage link", {algo:"xpath=//meta[@property='og:url']/@content",selected: true,languages: ["en","fr"] }
create_source "Organized by", {algo:"manual=Festival des Arts de Saint-Sauveur" }
create_source "Produced by", {algo:"manual=Enter the organization that produced this event"}
create_source "Performed by", {algo:"manual=Enter the organization that performed this event"}
create_source "Tickets link", {algo:"xpath=//*[(@id = 'programmation-header')]//a[@class='accueil_artistes_bt']/@href", selected: true,languages: ["en","fr"] }
create_source "Photo", {algo:"xpath=//meta[@property='og:image']/@content"}
create_source "Location", {algo:"xpath=//*[(@id = 'programmation-header')]//a[@class='accueil_artistes_bt']/@href", next_algo: "css=.tableCell1_oo:nth-child(3)"}
create_source "Start date", {algo:"xpath=//*[(@id = 'programmation-header')]//a[@class='accueil_artistes_bt']/@href", next_algo: "css=.tableCell1_oo:nth-child(1);css=.tableCell1_oo:nth-child(2);css=.tableCell1_oe:nth-child(1);css=.tableCell1_oe:nth-child(2);ruby=$array.each_slice(2).map {|n| n.first + ' ' + n.second}"}

create_source "Name", {rdfs_class_id: 3, algo: "css=#content li:nth-child(1);ruby=$array.first.split(',')[0]", selected: true, languages: ["en","fr"]}
create_source "Name", {rdfs_class_id: 3, algo: "manual=Grand Chapiteau FASS Big Top", selected: false}


create_source "Event type", {algo: "manual=Live performance"}
create_source "Name", {rdfs_class_id: 4, algo: "manual=Live performance"}
