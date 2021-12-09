class Resource 
  include StatementsHelper
  include ResourcesHelper
  attr_accessor :statements, :rdfs_class, :seedurl, :archive_date, :webpages, :rdf_uri

  def initialize(rdf_uri)
    @rdf_uri = rdf_uri
    @statements = {}

    @webpages = Webpage.where(rdf_uri: @rdf_uri).order(:archive_date) 
    @rdfs_class = @webpages.first.rdfs_class.name if !@webpages.empty?
    @seedurl = @webpages.first.website.seedurl if !@webpages.empty?
    @archive_date = @webpages.last.archive_date if !@webpages.empty?  #get the lastest date for bilingual sites that have 2 archive_dates

    @webpages.each do |webpage|
      webpage.statements.each do |statement|
        property = build_key(statement) # StatementsHelper
        @statements[property] = {} if @statements[property].nil?
        # add statements that are 'not selected' as an alternative inside the selected statement
        if statement.source.selected
          @statements[property].merge!(adjust_labels_for_api(statement)) # ResourcesHelper
          @statements[property].merge!({ rdf_uri: @rdf_uri }) # each statement has a copy of the triple subject
        elsif statement.selected_individual
          @statements[property].merge!({individual_override: []}) if @statements[property][:individual_override].nil?
          @statements[property][:individual_override] << adjust_labels_for_api(statement) # ResourcesHelper
        else
          @statements[property].merge!({alternatives: []}) if @statements[property][:alternatives].nil?
          @statements[property][:alternatives] << adjust_labels_for_api(statement) # ResourcesHelper
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
