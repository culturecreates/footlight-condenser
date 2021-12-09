#json.extract!  @resource, :uri, :rdfs_class, :seedurl, :archive_date, :statements
json.uri @resource.rdf_uri
json.rdfs_class @resource.rdfs_class
json.seedurl @resource.seedurl
json.archive_date @resource.archive_date
json.statements @resource.statements