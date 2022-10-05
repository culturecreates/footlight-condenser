class Resource 
  include StatementsHelper
  include ResourcesHelper
  attr_accessor :rdfs_class, :seedurl, :archive_date, :webpages, :rdf_uri, :errors

  def initialize(rdf_uri, **extras)
    @rdf_uri = rdf_uri
  end

  def rdfs_class
    @webpages ||= Webpage.where(rdf_uri: @rdf_uri)
    @rdfs_class ||=  @webpages.first.rdfs_class.name if !@webpages.empty?
    @rdfs_class
  end

  # Create a resouces with dummy webpage (uri) and statements
  # statements shape: { name: {value: "my name", language: "en" },  name: {value: "my name", language: "en", rdfs_class_name: "PostalAddress"}}
  # if statements fail because source missing, then delete dummy webpages
  def save(new_statements = {})
    webpage = create_webpage_uri
    sources = webpage.website.sources
  
    # For each statements loop
    webpage_has_atleast_one_statement = false
    new_statements.each do |stat_name, stat|
      # determine the class of the property using the class passed with the property, or else use the webpage class.
      prop_rdfs_class = if stat["rdfs_class_name"]
                          RdfsClass.where(name: stat["rdfs_class_name"]).first
                        else
                          webpage.rdfs_class
                        end
      prop = Property.where(label: stat_name.to_s.titleize, rdfs_class: prop_rdfs_class).first
      src = sources.where(language: stat[:language], property: prop)
      if src.count > 0
        stat = Statement.new(status: "ok", manual: true, selected_individual: true, source: src.first, webpage: webpage, cache: stat[:value])
        if stat.save 
          webpage_has_atleast_one_statement = true
        end
      else
        Rails.logger.error "No source exists. Could not create statement for prop #{stat_name} #{stat.inspect} for page #{webpage.inspect}."
      end
    end
    if !webpage_has_atleast_one_statement
      delete_webpage(webpage)
      @errors = { error: "No sources exist for any property. Webpage deleted." }
      return false
    end
    true
  end

  # Create a Webpage using rdfs_class, rdf_uri
  def create_webpage_uri 
    website = Website.where(seedurl: @seedurl).first
    page = Webpage.new
    page.website = website
    page.rdf_uri =  @rdf_uri
    page.rdfs_class = RdfsClass.where(name: @rdfs_class).first
    page.url = @rdf_uri
    page.language = website.default_language
    page.save
    return page
  end

  def delete_webpage(webpage)
    # used when a fake webpage is created when minted Footlight resources, but the resource had an error
    webpage.destroy
    Rails.logger.info "Deleting webpage #{webpage.inspect}"
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
