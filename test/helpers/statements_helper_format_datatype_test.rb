require 'test_helper'

# StatementsHolder tests for format_datatype() only.
class StatementsHelperTest < ActionView::TestCase
  tests StatementsHelper

  # Removed test JAN 2022 - it was a bad idea to use manual source with array input.
  # Instead use manual=Place des Arts
  #
  # test "prexisting array input for any:URI manual source" do
  #   property = properties(:seven)
  #   scraped_data = ["[\"name\",\"Class\",[\"remote name\",\"uri\"]]"]
  #   webpage = webpages(:one)
  #   actual = format_datatype(scraped_data, property, webpage)
  #   expected = ["name", "Class", ["remote name", "uri"]]
  #   assert_equal expected, actual
  # end

  test "string input for any:URI manual source" do
    property = properties(:seven)
    scraped_data = ["Théâtre Maisonneuve"]
    webpage = webpages(:one)
    VCR.use_cassette('StatementsHelper_format_datatype') do
      actual = format_datatype(scraped_data, property, webpage)
      expected = ["Théâtre Maisonneuve", "Place", ["Place des Arts - Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/K11-11"]]
      assert_equal expected, actual
    end
  end

  # TODO: match on URL
  # test "string input for any:URI scraped source" do
  #   property = properties(:nine)
  #   scraped_data = ["http://www.tnb.nb.ca/"]
  #   webpage = webpages(:one)
  #   actual = format_datatype(scraped_data, property, webpage)
  #   expected = ["http://www.tnb.nb.ca/", "Organization", ["Theatre New Brunswick", "http://kg.artsdata.ca/resource/K10-168"]]
  #   assert_equal expected, actual
  #  end

  # TODO: match on URL
  # test "string input for any:URI scraped LONG url source" do
  #   property = properties(:nine)
  #   scraped_data = ["www.taramacleanmusic.com"]
  #   webpage = webpages(:one)
  #   actual = format_datatype(scraped_data, property, webpage)
  #   expected = ["http://www.taramacleanmusic.com/home", "Organization", ["Tara MacLean", "http://kg.artsdata.ca/resource/K12-14"]]
  #   assert_equal expected, actual
  #  end

  test "EMPTY string input for any:URI" do
    property = properties(:nine)
    scraped_data = []
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = []
    assert_equal expected, actual
  end

  test "array string input for any:URI" do
    property = properties(:nine)
    scraped_data = ["CompanyKaha:wi Dance Theatre","ArtistsSantee Smith"]
    webpage = webpages(:one)
    expected = [["CompanyKaha:wi Dance Theatre", "Organization", ["Kaha:wi Dance Theatre", "http://kg.artsdata.ca/resource/K10-206"]], ["ArtistsSantee Smith", "Organization"]]
    VCR.use_cassette('StatementsHelper array string input for any:URI') do
      assert_equal expected, format_datatype(scraped_data, property, webpage)
    end
  end

  test "format_datatype with time_zone" do
    property = properties(:ten)
    scraped_data = ["time_zone:  Eastern Time (US & Canada) ","2020-05-28T22:00:00-00:00", "2020-05-31T22:00:00-00:00"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["2020-05-28T18:00:00-04:00", "2020-05-31T18:00:00-04:00"]
    assert_equal expected, actual
  end

  test "format_datatype with NO time_zone" do
    property = properties(:ten)
    scraped_data = ["2020-05-28T22:00:00-01:00", "2020-05-31T22:00:00-01:00"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["2020-05-28T19:00:00-04:00", "2020-05-31T19:00:00-04:00"]
    assert_equal expected, actual
  end

  test "format_datatype with INVALID time_zone" do
    property = properties(:ten)
    scraped_data = ["time_zone:  Nowhere Time (US & Canada) ","2020-05-28T22:00:00-01:00", "2020-05-31T22:00:00-01:00"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Bad input for date/time: 2020-05-28T22:00:00-01:00.  (#<ArgumentError: Invalid Timezone: Nowhere Time (US & Canada)>)", "Bad input for date/time: 2020-05-31T22:00:00-01:00.  (#<ArgumentError: Invalid Timezone: Nowhere Time (US & Canada)>)"]
    assert_equal expected, actual
  end

  test "format_datatype EventStatus with cancelled" do
    property = properties(:twelve)
    scraped_data = ["Cancelled - Bob Marley live"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Cancelled - Bob Marley live", "EventStatusType", ["EventCancelled", "http://schema.org/EventCancelled"]]
    assert_equal expected, actual
  end

  test "format_datatype EventStatus with postponed" do
    property = properties(:twelve)
    scraped_data = ["Bob Marley live postponed"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Bob Marley live postponed", "EventStatusType", ["EventPostponed", "http://schema.org/EventPostponed"]]
    assert_equal expected, actual
  end

  test "format_datatype EventStatus with rescheduled" do
    property = properties(:twelve)
    scraped_data = ["Bob Marley live Rescheduled"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Bob Marley live Rescheduled", "EventStatusType", ["EventRescheduled", "http://schema.org/EventRescheduled"]]
    assert_equal expected, actual
  end

  test "format_datatype EventStatus with scheduled" do
    property = properties(:twelve)
    scraped_data = ["Bob Marley live"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Bob Marley live", "EventStatusType", ["EventScheduled", "http://schema.org/EventScheduled"]]
    assert_equal expected, actual
  end

  test "format_datatype EventStatus with hidden rescheduled" do
    property = properties(:twelve)
    scraped_data = ["Bob Marley live with the amazing derescheduled"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Bob Marley live with the amazing derescheduled", "EventStatusType", ["EventScheduled", "http://schema.org/EventScheduled"]]
    assert_equal expected, actual
  end

  test "link to additionalType schema:ComedyEvent" do
    property = properties(:additionalType)
    scraped_data = ["Humour | Programmation distanciée"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Humour | Programmation distanciée", "EventTypeEnumeration", ["ComedyEvent", "http://schema.org/ComedyEvent"]]
    assert_equal expected, actual
  end

  test "link to additionalType ado:ComedyEvent" do
    property = properties(:additionalTypeADO)
    scraped_data = ["Humour | Programmation distanciée"]
    webpage = webpages(:one)
    expected = ["Humour | Programmation distanciée", "EventType", ["Humour", "http://kg.artsdata.ca/resource/ComedyPerformance"]]
    VCR.use_cassette('StatementsHelper link to additionalType ado:ComedyEvent') do
      assert_equal expected, format_datatype(scraped_data, property, webpage)
    end
  end

  test "link to attendanceMode In-person" do
    property = properties(:AttendanceMode)
    scraped_data = ["OfflineEventAttendanceMode detected in event"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["OfflineEventAttendanceMode detected in event", "EventAttendanceModeEnumeration", ['In-person', 'http://schema.org/OfflineEventAttendanceMode']]
    assert_equal expected, actual
  end
end
