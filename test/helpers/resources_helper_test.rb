require 'test_helper'

class ResourcesHelperTest < ActionView::TestCase

  test "get website uris per type" do
    website =  websites(:musiconmain)
    expected =  [{uri:"adr:eight",name:"My Name"}]
    actual = get_uris(website.seedurl, "Person")
    assert_equal expected, actual
  end

end
