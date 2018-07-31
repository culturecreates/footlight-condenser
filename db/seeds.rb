# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)


RdfsClass.create!(name: "Event")
RdfsClass.create!(name: "Organisation")
RdfsClass.create!(name: "Place")


Property.create!(label:  "Title", rdfs_class_id: 1)
Property.create!(label:  "Date", value_datatype: "xsd:date", rdfs_class_id: 1)
Property.create!(label:  "Photo", rdfs_class_id: 1)
Property.create!(label:  "Description", rdfs_class_id: 1)
Property.create!(label:  "Location", rdfs_class_id: 1)
Property.create!(label:  "Organized by", rdfs_class_id: 1)
Property.create!(label:  "Time", value_datatype: "xsd:time", rdfs_class_id: 1)
Property.create!(label:  "Duration", rdfs_class_id: 1)
Property.create!(label:  "Tickets link", rdfs_class_id: 1)
Property.create!(label:  "Webpage link", rdfs_class_id: 1)
Property.create!(label:  "Produced by", rdfs_class_id: 1)
Property.create!(label:  "Performed by", rdfs_class_id: 1)


@site = Website.create!(seedurl: "fass.ca")

pages_en = [
"http://festivaldesarts.ca/en/performances/feature-presentations/romeo-et-juliette/",
"http://festivaldesarts.ca/en/performances/feature-presentations/toronto-dance-theater/",
"http://festivaldesarts.ca/en/performances/feature-presentations/orchestre-metropolitain/",
"http://festivaldesarts.ca/en/performances/feature-presentations/hubbard-street-dance-chicago/",
"http://festivaldesarts.ca/en/performances/feature-presentations/yemen-blues/",
"http://festivaldesarts.ca/en/performances/feature-presentations/a-night-with-the-stars/",
"http://festivaldesarts.ca/en/performances/feature-presentations/guillaume-cote/"
]
pages_fr = [
"http://festivaldesarts.ca/programmation/en-salle/romeo-et-juliette/",
"http://festivaldesarts.ca/programmation/en-salle/toronto-dance-theater/",
"http://festivaldesarts.ca/programmation/en-salle/orchestre-metropolitain/",
"http://festivaldesarts.ca/programmation/en-salle/hubbard-street-dance-chicago/",
"http://festivaldesarts.ca/programmation/en-salle/yemen-blues/",
"http://festivaldesarts.ca/programmation/en-salle/soiree-des-etoiles/",
"http://festivaldesarts.ca/programmation/en-salle/guillaume-cote/",
"http://festivaldesarts.ca/programmation/en-salle/orchestre-metropolitain-2/",
"http://festivaldesarts.ca/programmation/en-salle/soiree-des-etoiles-2/"
]

pages_en.each do |page|
  Webpage.create!(url: page, website: @site, rdfs_class: RdfsClass.where(name: "Event").first, language: "en", rdf_uri: page.split("/")[2].sub(".","-") + "_" + page.split("/")[6])
end

pages_fr.each do |page|
 Webpage.create!(url: page, website: @site, rdfs_class: RdfsClass.where(name: "Event").first, language: "fr", rdf_uri: page.split("/")[2].sub(".","-") + "_" + page.split("/")[5])
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
create_source("Produced by","xpath=//meta[@property='og:site_name']/@content")
create_source("Tickets link","xpath=//a[@class='accueil_artistes_bt']/@href","",true,["en","fr"])
create_source("Photo","xpath=//meta[@property='og:image']/@content")

create_source("Date","xpath=//a[@class='accueil_artistes_bt']/@href","css=.tableCell1_oo:nth-child(1),css=.tableCell1_oe:nth-child(1)")
create_source("Time","xpath=//a[@class='accueil_artistes_bt']/@href","css=.tableCell1_oo:nth-child(2),css=.tableCell1_oe:nth-child(2)")
create_source("Location","xpath=//a[@class='accueil_artistes_bt']/@href","css=.tableCell1_oo:nth-child(3)")
