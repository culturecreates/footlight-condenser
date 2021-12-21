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
    
      Statement.includes(:webpage)
      .where(selected_individual: true)
      .where(status: ["ok","initial","updated"])
      .where({ webpages: { rdf_uri: @rdf_uri } })
      .update_all(status: "ok", status_origin: status_origin)
      
  end
end
