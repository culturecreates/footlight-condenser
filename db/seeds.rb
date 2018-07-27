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

["en","fr"].each do |lang|
  Property.create!(label:  "Title",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Date",language: lang, value_datatype: "xsd:date", rdfs_class_id: 1)
  Property.create!(label:  "Photo",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Description",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Location",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Organized by",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Time",language: lang, value_datatype: "xsd:time", rdfs_class_id: 1)
  Property.create!(label:  "Duration",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Tickets link",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Webpage link",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Produced by",language: lang, rdfs_class_id: 1)
  Property.create!(label:  "Performed by",language: lang, rdfs_class_id: 1)
end

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


def self.create_source(label, algo, next_algo)
  ["en","fr"].each do |lang|
    if !next_algo.blank?
      s = Source.create!(render_js: true, website: @site, property: Property.where(label: label, language:lang).first, algorithm_value:next_algo, selected:true)
      Source.create!(next_step: s.id, website: @site, property: Property.where(label: label, language:lang).first, algorithm_value:algo, selected:true)
    else
      Source.create!(website: @site, property: Property.where(label: label, language:lang).first, algorithm_value:algo, selected:true)
    end
  end
end

create_source("Title","xpath=//meta[@property='og:title']/@content","")
create_source("Description","xpath=//comment()[.='OVERVIEW CONTENT']/following-sibling::div[1]","")
create_source("Webpage link","xpath=//meta[@property='og:url']/@content","")
create_source("Photo","xpath=//meta[@property='og:image']/@content","")

create_source("Date","xpath=//a[@class='accueil_artistes_bt']/@href","css=.tableCell1_oo:nth-child(1),css=.tableCell1_oe:nth-child(1)")
