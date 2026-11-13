require "test_helper"

class ExportArtsdataServiceTest < ActiveSupport::TestCase
  test "matches publishable events output from events controller logic" do
    seedurl = websites(:one).seedurl

    expected = JsonldGenerator.dump_events(EventsController.new.publishable_events(seedurl))
    actual = ExportArtsdataService.call(seedurl: seedurl)

    assert_equal expected, actual
  end
end
