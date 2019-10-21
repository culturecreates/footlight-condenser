
# rails db:seed:base

puts "starting class seeds..."

RdfsClass.create!(name: "Event")
RdfsClass.create!(name: "Organization")
RdfsClass.create!(name: "Place")
RdfsClass.create!(name: "Category")
RdfsClass.create!(name: "EventSeries")


Property.create!(label:  "Title", rdfs_class_id: 1, uri: "http://schema.org/name")
Property.create!(label:  "Date", value_datatype: "xsd:date", rdfs_class_id: 1, uri: "")
Property.create!(label:  "Photo", rdfs_class_id: 1, uri: "http://schema.org/image")
Property.create!(label:  "Description", rdfs_class_id: 1, uri: "http://schema.org/description")
Property.create!(label:  "Location", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Place", uri: "http://schema.org/location")
Property.create!(label:  "Organized by", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Organization", uri: "http://schema.org/organizer")
Property.create!(label:  "Time", value_datatype: "xsd:time", rdfs_class_id: 1, uri: "")
Property.create!(label:  "Duration", rdfs_class_id: 1, value_datatype: "xsd:duration", uri: "http://schema.org/Duration")
Property.create!(label:  "Tickets link", rdfs_class_id: 1, uri: "http://schema.org/offer:url")
Property.create!(label:  "Webpage link", rdfs_class_id: 1, uri: "http://schema.org/url")
Property.create!(label:  "Produced by",  value_datatype: "xsd:anyURI",rdfs_class_id: 1, expected_class: "Organization", uri: "http://schema.org/composer")
Property.create!(label:  "Performed by", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Organization", uri: "http://schema.org/performer")
Property.create!(label:  "Start date", value_datatype: "xsd:dateTime", rdfs_class_id: 1, uri: "http://schema.org/startDate")
Property.create!(label:  "Event type", value_datatype: "xsd:anyURI", rdfs_class_id: 1, expected_class: "Category", uri: "")
Property.create!(label:  "Title", rdfs_class_id: 5,  uri: "http://schema.org/name")
Property.create!(label:  "subEvent", value_datatype: "bnode", rdfs_class_id: 5, expected_class: "Event")


#Other Class properties
Property.create!(label:  "Name", rdfs_class_id: 3)
Property.create!(label:  "Name", rdfs_class_id: 4)
