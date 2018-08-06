module ResourcesHelper

  def get_uris seedurl, rdfs_class_name
    uri_list = []
    website = Website.where(seedurl: seedurl).first
    if !website.nil?
      rdfs_class = RdfsClass.where(name: rdfs_class_name).first
      webpages = website.webpages.where(rdfs_class: rdfs_class)
      webpages.each {|page| uri_list << {rdf_uri: page.rdf_uri}}
      uri_list.uniq!
    end
    return uri_list
  end


  def calculate_resource_status statements
    resource_status = {never_reviewed:0, never_reviewed_flag:0, reviewed: 0, reviewed_flag:0, needs_review:0, needs_review_flag: 0}
    statements.each do |s|
      resource_status[s.status] = 0 if resource_status[s.status].nil?
      resource_status[s.status] += 1
    end
    return resource_status
  end

end
