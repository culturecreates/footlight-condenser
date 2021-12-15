class Resource 
  include StatementsHelper
  include ResourcesHelper
  attr_accessor :statements, :rdfs_class, :seedurl, :archive_date, :webpages, :rdf_uri


  # DATA MODEL
  #  "uri": "adr:spec-qc-ca_chaakapesh",
  # "rdfs_class": "Event",
  # "seedurl": "spec-qc-ca",
  # "archive_date": "2021-02-07T04:59:00.000Z",
  # "statements": {
  #   "webpage_link_fr": {
  #     "id": 84138,
  #     "status": "ok",
  #     "status_origin": "Gregory Saumier-Finch",
  #     "cache_refreshed": "2021-12-09T23:09:48.457Z",
  #     "cache_changed": null,
  #     "source_id": 691,
  #     "webpage_id": 5667,
  #     "created_at": "2021-02-05T09:04:29.085Z",
  #     "updated_at": "2021-12-09T23:09:48.462Z",
  #     "selected_individual": false,
  #     "value": "https://spec.qc.ca/spectacle/chaakapesh",
  #     "label": "Webpage link",
  #     "language": "fr",
  #     "source_label": "",
  #     "datatype": "",
  #     "expected_class": "",
  #     "uri": "http://schema.org/url",
  #     "manual": false,
  #     "rdf_uri": "adr:spec-qc-ca_chaakapesh",
  #     "alternatives": [{}]

  def initialize(rdf_uri)
    @rdf_uri = rdf_uri
    @statements = {}

    @webpages = Webpage.where(rdf_uri: @rdf_uri).order(:archive_date) 
    @rdfs_class = @webpages.first.rdfs_class.name if !@webpages.empty?
    @seedurl = @webpages.first.website.seedurl if !@webpages.empty?
    @archive_date = @webpages.last.archive_date if !@webpages.empty?  #get the lastest date for bilingual sites that have 2 archive_dates

    override = [] # add properties that are selected_individuals, putting regular selected source for those properties into alternatives
    @webpages.each do |webpage|
      webpage.statements.order(selected_individual: :desc).each do |statement|
        property = build_key(statement) # StatementsHelper
        @statements[property] = {} if @statements[property].nil?
        # add statements that are 'not selected' as an alternative inside the selected statement
        if statement.selected_individual
          @statements[property].merge!(adjust_labels_for_api(statement, subject: @rdf_uri, webpage_class_name: @rdfs_class )) # ResourcesHelper
          override << property
        elsif statement.source.selected && !override.include?(property)
          @statements[property].merge!(adjust_labels_for_api(statement, subject: @rdf_uri, webpage_class_name: @rdfs_class)) # ResourcesHelper
        else
          @statements[property].merge!({alternatives: []}) if @statements[property][:alternatives].nil?
          @statements[property][:alternatives] << adjust_labels_for_api(statement, subject: @rdf_uri, webpage_class_name: @rdfs_class) # ResourcesHelper
        end
      end
    end
    
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
