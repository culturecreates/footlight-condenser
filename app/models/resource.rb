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

    override = [] # add properties that are selected_individuals, putting regular selected source for those properties into alternatives
    @webpages.each do |webpage|
      webpage.statements.order(selected_individual: :desc).each do |statement|
        @statements, override = build_nested_statement(@statements, statement, override: override, subject: @rdf_uri, webpage_class_name: @rdfs_class )
      end
    end
    @statements
  end



end



# @resource = { uri: params[:rdf_uri],
#   rdfs_class: "",
#   seedurl: "",
#   archive_date: "",
#   statements: {}}

# webpages = Webpage.where(rdf_uri: params[:rdf_uri]).order(:archive_date) 
# @resource[:rdfs_class] = webpages.first.rdfs_class.name if !webpages.empty?
# @resource[:seedurl] = webpages.first.website.seedurl if !webpages.empty?
# @resource[:archive_date] = webpages.last.archive_date if !webpages.empty?  #get the lastest date for bilingual sites that have 2 archive_dates

# webpages.each do |webpage|
# webpage.statements.each do |statement|
# property = helpers.build_key(statement)
# @resource[:statements][property] = {} if @resource[:statements][property].nil?
# #add statements that are 'not selected' as an alternative inside the selected statement
# if statement.source.selected
# @resource[:statements][property].merge!(helpers.adjust_labels_for_api(statement))
# @resource[:statements][property].merge!({rdf_uri:params[:rdf_uri] })
# # elsif statement.selected_individual
# #   @resource[:statements][property].merge!({indivisual_override: []}) if @resource[:statements][property][:indivisual_override].nil?
# #   @resource[:statements][property][:indivisual_override] << helpers.adjust_labels_for_api(statement)
# # else
# @resource[:statements][property].merge!({alternatives: []}) if @resource[:statements][property][:alternatives].nil?
# @resource[:statements][property][:alternatives] << helpers.adjust_labels_for_api(statement)
# end
# end
# end
# @statement_keys = @resource[:statements].keys.sort
