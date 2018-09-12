# rails db:seed:single SEED=dansedanse

@site = Website.create!(seedurl: "dansedanse-ca")

# ["URL","URI","en"], ["URL","URI","fr"]
pages = [
  ["https://www.dansedanse.ca/fr/dada-masilo-dance-factory-johannesburg-giselle","adr:dansedanse-ca_dada-masilo-dance-factory-johannesburg-giselle", "fr"],
  ["https://www.dansedanse.ca/en/dada-masilo-dance-factory-johannesburg-giselle","adr:dansedanse-ca_dada-masilo-dance-factory-johannesburg-giselle","en"],
  ["https://www.dansedanse.ca/fr/sylvain-lafortune-esther-rousseau-morin-lun-lautre","adr:dansedanse-ca_sylvain-lafortune-esther-rousseau-morin-lun-lautre", "fr"],
  ["https://www.dansedanse.ca/en/sylvain-lafortune-esther-rousseau-morin-lun-lautre","adr:dansedanse-ca_sylvain-lafortune-esther-rousseau-morin-lun-lautre","en"],
  ["https://www.dansedanse.ca/fr/gauthier-dance-dance-company-theaterhaus-stuttgart-0","adr:dansedanse-ca_gauthier-dance-dance-company-theaterhaus-stuttgart-0", "fr"],
  ["https://www.dansedanse.ca/en/gauthier-dance-theaterhaus-stuttgart","adr:dansedanse-ca_gauthier-dance-dance-company-theaterhaus-stuttgart-0","en"],
  ["https://www.dansedanse.ca/fr/tentacle-tribe-ghost","adr:dansedanse-ca_tentacle-tribe-ghost", "fr"],
  ["https://www.dansedanse.ca/en/tentacle-tribe-ghost","adr:dansedanse-ca_tentacle-tribe-ghost","en"],
  ["https://www.dansedanse.ca/fr/groupe-rubberbandance-vraiment-doucement","adr:dansedanse-ca_groupe-rubberbandance-vraiment-doucement", "fr"],
  ["https://www.dansedanse.ca/en/groupe-rubberbandance-vraiment-doucement","adr:dansedanse-ca_groupe-rubberbandance-vraiment-doucement","en"],
  ["https://www.dansedanse.ca/fr/grupo-corpo-bach-gira","adr:dansedanse-ca_grupo-corpo-bach-gira", "fr"],
  ["https://www.dansedanse.ca/en/grupo-corpo-bach-gira","adr:dansedanse-ca_grupo-corpo-bach-gira","en"],
  ["https://www.dansedanse.ca/fr/rosas-love-supreme","adr:dansedanse-ca_rosas-love-supreme", "fr"],
  ["https://www.dansedanse.ca/en/rosas-love-supreme","adr:dansedanse-ca_rosas-love-supreme","en"],
  ["https://www.dansedanse.ca/fr/akram-khan-company-xenos","adr:dansedanse-ca_akram-khan-company-xenos", "fr"],
  ["https://www.dansedanse.ca/en/akram-khan-company-xenos","adr:dansedanse-ca_akram-khan-company-xenos","en"],
  ["https://www.dansedanse.ca/fr/peggy-baker-dance-projects-who-we-are-dark","adr:dansedanse-ca_peggy-baker-dance-projects-who-we-are-dark", "fr"],
  ["https://www.dansedanse.ca/en/peggy-baker-dance-projects-who-we-are-dark","adr:dansedanse-ca_peggy-baker-dance-projects-who-we-are-dark","en"],
  ["https://www.dansedanse.ca/fr/bjm-les-ballets-jazz-de-montreal-dance-me","adr:dansedanse-ca_bjm-les-ballets-jazz-de-montreal-dance-me", "fr"],
  ["https://www.dansedanse.ca/en/bjm-les-ballets-jazz-de-montreal-dance-me","adr:dansedanse-ca_bjm-les-ballets-jazz-de-montreal-dance-me","en"],
  ["https://www.dansedanse.ca/fr/red-sky-performance-backbone","adr:dansedanse-ca_red-sky-performance-backbone", "fr"],
  ["https://www.dansedanse.ca/en/red-sky-performance-backbone","adr:dansedanse-ca_red-sky-performance-backbone","en"],
  ["https://www.dansedanse.ca/fr/kidd-pivot-revisor","adr:dansedanse-ca_kidd-pivot-revisor", "fr"],
  ["https://www.dansedanse.ca/en/kidd-pivot-revisor","adr:dansedanse-ca_kidd-pivot-revisor","en"],
  ["https://www.dansedanse.ca/fr/alonzo-king-lines-ballet-propelled-heart","adr:dansedanse-ca_alonzo-king-lines-ballet-propelled-heart", "fr"],
  ["https://www.dansedanse.ca/en/alonzo-king-lines-ballet-propelled-heart","adr:dansedanse-ca_alonzo-king-lines-ballet-propelled-heart","en"]
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
create_source("Title",{algo: "xpath=//h2[@itemprop='composer'];ruby=$array.map {|e| e + ' | Danse Danse'}", selected: false, languages: ["en","fr"]})
create_source("Title",{algo: "xpath=//h2[@itemprop='composer']", selected: false, languages: ["en","fr"]})
create_source("Description",{selected: false, algo: "xpath=//div[@itemprop='description'];ruby=$array.map {|t| t.squish}", languages: ["en","fr"]})
create_source("Description",{algo: "xpath=//span[@class='txt-saison']", languages: ["en","fr"]})
create_source("Photo",{algo: "xpath=//img[@typeof='foaf:Image']/@src;ruby=$array.first"})
create_source("Photo",{selected: false, algo: "xpath=//img[@typeof='foaf:Image']/@src;ruby=$array.first"})
create_source("Photo",{selected: false, algo: "xpath=//img[@typeof='foaf:Image']/@src;ruby=$array[1]"})
create_source("Photo",{selected: false, algo: "xpath=//img[@typeof='foaf:Image']/@src;ruby=$array[2]"})
create_source("Photo",{selected: false, algo: "xpath=//img[@typeof='foaf:Image']/@src;ruby=$array[3]"})
create_source("Location",{algo: "xpath=//span[@itemprop='name address']"})
create_source("Start date",{algo: "xpath=//span[@class='date-display-single']"})
create_source("Organized by",{algo: "manual=Danse Danse"})
create_source("Produced by",{algo: "xpath=//h2[@itemprop='composer']"})
create_source("Performed by",{algo: "xpath=//span[@itemprop='performer'];ruby=$array.map {|p| p.squish}.join(', ').split('*')"})
create_source("Tickets link",{algo: "xpath=//a[@class='button btn-saison fullwidth']/@href", languages: ["en","fr"]})
create_source("Webpage link",{algo: "ruby=$url", languages: ["en","fr"]})
create_source("Duration", {algo: "xpath=//span[@id='duree'];ruby=$array.map {|s| s.squish.gsub(/min/,'') + ' minute '}"})


create_source("Event type", {algo: "manual=Live performance"})
create_source("Name", {rdfs_class_id: 4, algo: "manual=Live performance"})
