# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)


RdfsClass.create!(name: "Event")
RdfsClass.create!(name: "Organization")
RdfsClass.create!(name: "Place")


Property.create!(label:  "Title", rdfs_class_id: 1)
Property.create!(label:  "Date", value_datatype: "xsd:date", rdfs_class_id: 1)
Property.create!(label:  "Photo", rdfs_class_id: 1)
Property.create!(label:  "Description", rdfs_class_id: 1)
Property.create!(label:  "Location", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Place")
Property.create!(label:  "Organized by", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Organization")
Property.create!(label:  "Time", value_datatype: "xsd:time", rdfs_class_id: 1)
Property.create!(label:  "Duration", rdfs_class_id: 1, value_datatype: "xsd:duration", uri: "http://schema.org/Duration")
Property.create!(label:  "Tickets link", rdfs_class_id: 1)
Property.create!(label:  "Webpage link", rdfs_class_id: 1)
Property.create!(label:  "Produced by",  value_datatype: "xsd:anyURI",rdfs_class_id: 1, expected_class: "Organization")
Property.create!(label:  "Performed by", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Organization")
Property.create!(label:  "Start date", value_datatype: "xsd:dateTime", rdfs_class_id: 1, uri: "http://schema.org/startDate")
Property.create!(label:  "Event type", value_datatype: "xsd:anyURI", rdfs_class_id: 1)


#Place properties
Property.create!(label:  "Name", rdfs_class_id: 3)


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



place_pages_en = ["http://festivaldesarts.ca/en/visitors-infos/"]
place_pages_fr = ["http://festivaldesarts.ca/infos-visiteurs/"]

place_pages_en.each do |page|
  Webpage.create!(url: page, website: @site, rdfs_class: RdfsClass.where(name: "Place").first, language: "en", rdf_uri: "adr:festivaldesarts-ca_visitors-infos")
end

place_pages_fr.each do |page|
 Webpage.create!(url: page, website: @site, rdfs_class: RdfsClass.where(name: "Place").first, language: "fr", rdf_uri: "adr:festivaldesarts-ca_visitors-infos")
end



def self.create_source( label, algo, next_algo = "", selected = true, languages = [""])

  languages.each do |lang|
    if !next_algo.blank?
      s = Source.create!(language: lang, render_js: true, website: @site, property: Property.where(label: label).first, algorithm_value:next_algo, selected:selected)
      Source.create!(language: lang, next_step: s.id, website: @site, property: Property.where(label: label).first, algorithm_value:algo, selected:selected)
    else
      Source.create!(language: lang, website: @site, property: Property.where(label: label).first, algorithm_value:algo, selected:selected)
    end
  end
end

create_source("Title","xpath=//meta[@property='og:title']/@content","",true,["en","fr"])
create_source("Description","xpath=//meta[@property='og:description']/@content","",false,["en","fr"])
create_source("Description","css=.fw-row :nth-child(1) .textblock-shortcode p:nth-child(1)","",true,["en","fr"])
create_source("Webpage link","xpath=//meta[@property='og:url']/@content","",true,["en","fr"])
create_source("Organized by","xpath=//meta[@property='og:site_name']/@content")
create_source("Produced by","manual=Enter the organization that produced this event")
create_source("Performed by","manual=Enter the organization that performed this event")
create_source("Tickets link","xpath=//*[(@id = 'programmation-header')]//a[@class='accueil_artistes_bt']/@href","",true,["en","fr"])
create_source("Photo","xpath=//meta[@property='og:image']/@content")

create_source("Location","xpath=//*[(@id = 'programmation-header')]//a[@class='accueil_artistes_bt']/@href","css=.tableCell1_oo:nth-child(3)")
create_source("Start date","xpath=//*[(@id = 'programmation-header')]//a[@class='accueil_artistes_bt']/@href","css=.tableCell1_oo:nth-child(1);css=.tableCell1_oo:nth-child(2);css=.tableCell1_oe:nth-child(1);css=.tableCell1_oe:nth-child(2);ruby=$array.each_slice(2).map {|n| n.first + " " + n.second}")


create_source("Name","css=#content li:nth-child(1)","",true,["en","fr"])
create_source("Name","url=https://fass.ticketpro.ca/?lang=fr&aff=fass#def_1277542554,css=.tableCell1_oo:nth-child(3)","",false)
