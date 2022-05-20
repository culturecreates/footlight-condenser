class Resource 
  include StatementsHelper
  include ResourcesHelper
  attr_accessor :rdfs_class, :seedurl, :archive_date, :webpages, :rdf_uri

  def initialize(rdf_uri, **extras)
    @rdf_uri = rdf_uri
  end

  def rdfs_class
    @webpages ||= Webpage.where(rdf_uri: @rdf_uri)
    @rdfs_class ||=  @webpages.first.rdfs_class.name if !@webpages.empty?
    @rdfs_class
  end

  # Create a resouces with dummy webpage (uri) and statements
  # statements shape: { name: {value: "my name", language: "en" }}
  def save(new_statements = {})
    page = create_webpage_uri
    sources = page.website.sources
    sources.each do |s|
      puts "source #{s.property.inspect}"
    end
    # For each statements loop
    new_statements.each do |stat_name, stat|
      prop = Property.where(label: stat_name.to_s.titleize, rdfs_class: page.rdfs_class).first
      puts "prop #{prop.inspect}"
      src = sources.where(language: stat[:language], property: prop)
      if src.count > 0
        stat = Statement.new(status: "ok", manual: true, selected_individual: true, source: src.first, webpage: page, cache: stat[:value])
        stat.save 
        puts "saved #{stat.inspect}"
      else
        puts "no source for prop #{prop.inspect}"
      end
    end

  end

  # Create a Webpage using rdfs_class, rdf_uri
  def create_webpage_uri 
    page = Webpage.new
    page.website = Website.where(seedurl: @seedurl).first
    page.rdf_uri =  @rdf_uri
    page.rdfs_class = RdfsClass.where(name: @rdfs_class).first
    page.url = @rdf_uri
    page.save
    return page
  end


  # get all resource statements adjusted for API with nested alternatives
  def statements
    @statements = {}

    @webpages ||= Webpage.where(rdf_uri: @rdf_uri) 
    @rdfs_class ||= @webpages.first.rdfs_class.name if !@webpages.empty?
    @seedurl ||= @webpages.first.website.seedurl if !@webpages.empty?
    @archive_date ||= @webpages.order(:archive_date).last.archive_date if !@webpages.empty?  #get the lastest date for bilingual sites that have 2 archive_dates

    @webpages.each do |webpage|
      webpage.statements.each do |statement|
        @statements = build_nested_statement(@statements, statement,  subject: @rdf_uri, webpage_class_name: @rdfs_class )
      end
    end
    @statements
  end

  def review_all_resource_except_flagged(status_origin)
    # Select all statements of entity that are selected_individual
    # and are not problem state.
    
      statements = Statement.includes(:webpage)
      .where(selected_individual: true)
      .where(status: ["ok","initial","updated"])
      .where({ webpages: { rdf_uri: @rdf_uri } })
    
      statements.each do |stat|
        stat.update(status: "ok", status_origin: status_origin)
      end
  end
end
