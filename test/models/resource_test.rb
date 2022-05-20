require 'test_helper'

class ResourceTest < ActiveSupport::TestCase
  test "create new Place resource" do
    minted_uri = "footlight:#{SecureRandom.uuid}" 
    resource = Resource.new(minted_uri)
    resource.seedurl = "musiconmain-ca"
    resource.rdfs_class = "Place"
    resource.save({ name: {value: "my name", language: "en" }})

    assert true
  end

  test 'create_webpage_uri' do 
    minted_uri = "footlight:#{SecureRandom.uuid}" 
    resource = Resource.new(minted_uri)
    resource.seedurl = "musiconmain-ca"
    resource.rdfs_class = "Place"
    resource.create_webpage_uri

    assert true
  end
end
