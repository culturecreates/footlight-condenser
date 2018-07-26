# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)


ObjectClass.create!(name: "Event")

Status.create!(label:"Not reviewed")

["en","fr"].each do |lang|
  Predicate.create!(label:  "Title",language: lang)
  Predicate.create!(label:  "Date",language: lang)
end

site = Website.create!(seedurl: "fass.ca")

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
  Webpage.create!(url: page, website: site, object_class: ObjectClass.where(name: "Event").first, language: "en", object_uri: page.split("/")[2] + "_" + page.split("/")[6])
end

pages_fr.each do |page|
 Webpage.create!(url: page, website: site, object_class: ObjectClass.where(name: "Event").first, language: "fr", object_uri: page.split("/")[2] + "_" + page.split("/")[5])
end

["en","fr"].each do |lang|
  Source.create!(website: site, predicate: Predicate.where(label: "Title", language:lang).first, algorithm_value:"xpath=//meta[@property='og:title']/@content", selected:true)
  s = Source.create!(website: site, predicate: Predicate.where(label: "Date", language:lang).first, algorithm_value:"css=.tableCell1_oo:nth-child(1),css=.tableCell1_oo:nth-child(2)", selected:true)
  Source.create!(next_source_id: s.id, website: site, predicate: Predicate.where(label: "Date", language:lang).first, algorithm_value:"xpath=//a[@class='accueil_artistes_bt']/@href", selected:true)
end
