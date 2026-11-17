namespace :footlight do
  desc "Queue due explicitly enrolled preprocessing statements and check freshness; run hourly"
  task refresh_preprocessing: :environment do
    Preprocessing::Dispatcher.call
  end

  desc "Read-only pilot inventory; does not refresh, create policies or call remote APIs"
  task preprocessing_inventory: :environment do
    {646580 => "gatineau-cloud-RList", 663745 => "gatineau-cloud-RList", 2020881 => "culturemauricie_lepointdevente-com-RList"}.each do |id, expected|
      statement = Statement.includes(:source, webpage: [:website, :rdfs_class]).find_by(id: id)
      puts({ statement_id: id, expected_seedurl: expected, found: statement.present?, seedurl: statement&.webpage&.website&.seedurl,
        identity_matches: statement&.webpage&.website&.seedurl == expected, webpage_id: statement&.webpage_id,
        rdf_class: statement&.webpage&.rdfs_class&.name, source_id: statement&.source_id, property_id: statement&.source&.property_id,
        property69_resource_list_input_candidates: statement ? Statement.joins(:source, webpage: :rdfs_class)
          .where(webpages: { website_id: statement.webpage.website_id }, sources: { website_id: statement.webpage.website_id, property_id: 69 },
            rdfs_classes: { name: "ResourceList" }).pluck(:id) : [],
        manual: statement&.manual, refreshed: statement&.cache_refreshed, changed: statement&.cache_changed }.to_json)
    end
  end
end
