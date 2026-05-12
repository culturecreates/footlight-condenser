require 'test_helper'

# Part of StatmentsHelper. See other test files for search_cckg and format_datatype tests. 
# Keep this file unit-fast. Do not add recorded scrape/network tests here.
# Put recorded scrape coverage in test/integration/statements_helper_scrape_integration_test.rb.
class StatementsHelperTest < ActionView::TestCase
  include DslRunnerTestHelper

  setup do
    Distillator::FetchCacheStore.expects(:fetch).never
    Dsl::Support::WringerClient.any_instance.expects(:fetch).never
  end

#process algorithm
test "process_algorithm sparql preserves structured captcha aborts" do
  abort_payload = [
    "abort_update",
    {
      error: "captcha detected",
      error_type: "system_captcha",
      source: "wringer",
      step: "sparql"
    }
  ]
  stubs(:safe_wringer_call).returns(abort_payload)

  assert_equal abort_payload, process_algorithm(
    algorithm: "sparql={?s a schema:Event. ?s schema:name ?answer}",
    url: "https://example.org/captcha"
  )
  assert_no_wringer_requests
end

test "process_algorithm manual" do
  expected = ["Test"]
  assert_equal expected, process_algorithm(algorithm: "manual=Test", url: "http://culturecreates.com")
  assert_no_wringer_requests
end
#test "process_algorithm ruby syntax error" do
#  expected = ["abort_update", {:error=>"(eval):1: syntax error, unexpected end-of-input, expecting '}'", :error_type=>SyntaxError, :results_prior=>[], :algorithm_rescued=>"ruby=$array.each {|a| a"}]
#  algo = "ruby=$array.each {|a| a"
#  assert_equal expected, process_algorithm(algorithm: algo,  url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe")
test "process_algorithm ruby syntax error" do
  algo = "ruby=$array.each {|a| a"
  result = process_algorithm(algorithm: algo, url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe")
  assert_equal "abort_update", result[0]
  details = result[1]
  assert_kind_of Hash, details
  assert_equal "SyntaxError", details[:error_type]
  assert_includes details[:error].downcase, "syntax error"
  assert_no_wringer_requests
end

test "process_algorithm invalid algorithm prefix" do
  algo = "//title"
  result = process_algorithm(algorithm: algo,  url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe")
  assert_equal "abort_update", result.first
  assert_match(/Missing DSL prefix/, result.last[:error])
  assert_no_wringer_requests
end

test "process_algorithm_scrape_options adds wringer compatibility for plain helper calls" do
  options = process_algorithm_scrape_options({})

  assert_equal true, options[:wringer_compatibility]
end

test "process_algorithm_scrape_options preserves cache-backed refresh options" do
  options = process_algorithm_scrape_options(
    force_scrape_every_hrs: "1",
    log_context: { statement_id: 1, website_id: 2 }
  )

  assert_nil options[:wringer_compatibility]
  assert_equal "1", options["force_scrape_every_hrs"]
  assert_equal({ "statement_id" => 1, "website_id" => 2 }, options["log_context"])
end

test "process_algorithm_uses_cache_path is true for statement refresh context" do
  assert_equal true, process_algorithm_uses_cache_path?(
    website_id: 2,
    log_context: { statement_id: 1 }
  )
end

test "process_algorithm_uses_cache_path is false for plain helper extraction" do
  assert_equal false, process_algorithm_uses_cache_path?({})
end

test "process_algorithm_uses_cache_path is true for force_scrape_every_hrs" do
  assert_equal true, process_algorithm_uses_cache_path?(force_scrape_every_hrs: "24")
end

test "process_algorithm_uses_cache_path is true for explicit mode" do
  assert_equal true, process_algorithm_uses_cache_path?(mode: :internal)
end

  # french_to_english_month
  test "french_to_english_month: should covert french month mai to english" do
    expected_output = "7 MAY 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 mai 2019 - 20 h")
  end

  test "french_to_english_month: should covert accented french month fév to english" do
    expected_output = "7 FEB 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 fév 2019 - 20 h")
  end

  test "french_to_english_month: should covert capitalized french month fév to english" do
    expected_output = "7 FEB 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 Fév 2019 - 20 h")
  end

  test "french_to_english_month: should covert french month février to FEB with spacer" do
    expected_output = "7 FEB 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 Février 2019 - 20 h")
  end

  # ISO_dateTime
  test "ISO_dateTime: should convert to ISO date time" do
   expected_output = "2019-07-03T20:30:00-04:00"
   assert_equal expected_output, ISO_dateTime("3 juillet 2019 - 20 h 30")
  end

  test "ISO_dateTime: should convert août to ISO date time" do
   expected_output = "2019-08-09T20:30:00-04:00"
   assert_equal expected_output, ISO_dateTime("9 août 2019 - 20 h 30")
  end

  test "ISO_dateTime: should convert date and time range to ISO date start time" do
   expected_output = "2018-10-20T10:00:00-04:00"
   assert_equal expected_output, ISO_dateTime(" samedi 20 octobre 2018, de 10 h à 11 h ")
  end

  test "ISO_dateTime: should convert a date without time to Date instead of dateTime" do
    expected_output = "2020-05-31"
    assert_equal expected_output, ISO_dateTime("2020-05-31")
   end

  test "ISO_dateTime: should set timezone" do
    expected_output = "2020-05-31T18:00:00-04:00"
    assert_equal expected_output, ISO_dateTime("2020-05-31T22:00:00-00:00","Eastern Time (US & Canada)")
  end

  test "ISO_dateTime: should set timezone traversing day boundary" do
    expected_output = "2020-05-30T22:00:00-04:00"
    assert_equal expected_output, ISO_dateTime("2020-05-31T02:00:00-00:00","Eastern Time (US & Canada)")
  end


  test "ISO_dateTime: should convert text containing 'Halifax' to dateTime" do
    expected_output = "2020-03-06T19:00:00-05:00"
    assert_equal expected_output, ISO_dateTime("06 mar 2020   Halifax   19 h 00 ")
  end

  
  

  #ISO_duration(duration_str)
  test "ISO_duration: should convert to ISO duration" do
   expected_output = "PT8400S"
   assert_equal expected_output, ISO_duration("2 hrs 20 min")
  end

  test "ISO_duration: should convert 2 h to ISO duration" do
    expected_output = "PT7200S"
    assert_equal expected_output, ISO_duration("duration 2 h")
  end

  test "ISO_duration: should convert 2 h 30 to ISO duration" do
    expected_output = "PT9000S"
    assert_equal expected_output, ISO_duration("duration: 2 h 30 m")
  end

  test "ISO_duration: should find no duration" do
    expected_output = ""
    assert_equal expected_output, ISO_duration("There is nothing here")
  end

  # TODO: improve NLP of duration extraction
  # test "ISO_duration: should convert messy string to ISO duration" do
  #   expected_output = "PT3600S"
  #   assert_equal expected_output, ISO_duration(" samedi 20 octobre 2018, de 10 h à 11 h ")
  # end


  #process_linked_data_removal statement_cache, uri_to_delete, class_to_delete, label_to_delete
  test "process_linked_data_removal: delete a link added manually" do
    expected_output = []
    statement_cache = ["Manually added","Place",["Theatre1","http://uri.com"]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end

  test "process_linked_data_removal: delete a link added automatically" do
    expected_output = [["Auto","Place",["Theatre1","http://uri.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    statement_cache = ["Auto","Place",["Theatre1","http://uri.com"]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end

  test "process_linked_data_removal: delete a second link added automatically" do
    expected_output =[["Auto", "Place", ["Theatre9", "http://uri9.com"], ["Theatre1", "http://uri.com"]], ["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    statement_cache = ["Auto","Place",["Theatre9","http://uri9.com"],["Theatre1","http://uri.com"]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end


  test "process_linked_data_removal: delete a deleted link" do
    expected_output = [["Auto", "Place", ["Theatre9", "http://uri9.com"]]]
    statement_cache = [["Auto", "Place", ["Theatre9", "http://uri9.com"]], ["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end


  test "process_linked_data_removal: delete a second manually added link" do
    expected_output = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    statement_cache = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually added", "Place", ["Theatre2", "http://uri2.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri2.com","Place","Theatre2")
  end

  test "process_linked_data_removal: delete a second auto added link" do
    expected_output = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually added", "Place", ["Theatre2", "http://uri2.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"],["Theatre9", "http://uri9.com"]]]
    statement_cache = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually added", "Place", ["Theatre2", "http://uri2.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri9.com","Place","Theatre9")
  end

  test "process_linked_data_removal: delete when out of sync" do
    expected_output = [["https://www.atlanticballet.ca/en/home/","Organization", ["Ballet Atlantique Canada", "http://kg.artsdata.ca/resource/K10-16"]], ["Manually deleted", "Organization", ["Against the Grain Theatre", "http://kg.artsdata.ca/resource/K10-280"]]]
    statement_cache = [["https://www.atlanticballet.ca/en/home/","Organization", ["Ballet Atlantique Canada", "http://kg.artsdata.ca/resource/K10-16"]], ["Manually deleted", "Organization", ["Against the Grain Theatre", "http://kg.artsdata.ca/resource/K10-280"], ["Ballet Atlantique Canada", "http://kg.artsdata.ca/resource/K10-16"]]]

    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://kg.artsdata.ca/resource/K10-16","Organization","Ballet Atlantique Canada")
  end


  test "convert_datetime(scraped_data)" do
    expected_output = ["2002-01-10"]
    scraped_data = ["10-JAN-2002"]
    assert_equal expected_output, convert_datetime(scraped_data)
  end

  test "convert_datetime with string input" do
    expected_output = ["2002-01-10"]
    scraped_data = "10-JAN-2002"
    assert_equal expected_output, convert_datetime(scraped_data)
  end

  test "convert_datetime with array input" do
    expected_output = ["2002-01-10T20:00:00-05:00","2002-01-11"]
    scraped_data = ["10-JAN-2002 at 8pm","11-JAN-2002"]
    assert_equal expected_output, convert_datetime(scraped_data)
  end

  test "convert_datetime with array input duplicates using different text" do
    expected_output = ["2002-01-10","2002-01-11T20:00:00-05:00"]
    scraped_data = ["10-JAN-2002","11-JAN-2002  at 8pm","11-JAN-2002 8 pm"]
    assert_equal expected_output, convert_datetime(scraped_data)
  end


  # reconcile_attendance_mode

  test "reconcile_attendance_mode online" do
    scraped_data = ["The Show","OnlineEventAttendanceMode"]
    expected_output = ["The Show - OnlineEventAttendanceMode", "EventAttendanceModeEnumeration", ["Online", "http://schema.org/OnlineEventAttendanceMode"]]
    assert_equal expected_output, reconcile_attendance_mode(scraped_data)
  end

  test "reconcile_attendance_mode offline" do
    scraped_data = ["The Show","OfflineEventAttendanceMode"]
    expected_output = ["The Show - OfflineEventAttendanceMode", "EventAttendanceModeEnumeration",  ["In-person", "http://schema.org/OfflineEventAttendanceMode"]]
    assert_equal expected_output, reconcile_attendance_mode(scraped_data)
  end

  test "reconcile_attendance_mode mixed" do
    scraped_data = ["The Show","MixedEventAttendanceMode"]
    expected_output = ["The Show - MixedEventAttendanceMode", "EventAttendanceModeEnumeration", ["Mixed", "http://schema.org/MixedEventAttendanceMode"]]
    assert_equal expected_output, reconcile_attendance_mode(scraped_data)
  end


  test "reconcile_attendance_mode string input instead of array" do
    scraped_data = "The Show"
    expected_output = ["The Show", "EventAttendanceModeEnumeration"]
    assert_equal expected_output, reconcile_attendance_mode(scraped_data)
  end

  # reconcile_event_status

  test "reconcile_event_status cancelled in string" do
    scraped_data = "The Show is cancelled"
    expected_output = ["The Show is cancelled", "EventStatusType", ["EventCancelled", "http://schema.org/EventCancelled"]]
    assert_equal expected_output, reconcile_event_status(scraped_data)
  end

  test "reconcile_event_status cancelled in array" do
    scraped_data = ["The Show","cancelled"]
    expected_output = ["The Show - cancelled", "EventStatusType", ["EventCancelled", "http://schema.org/EventCancelled"]]
    assert_equal expected_output, reconcile_event_status(scraped_data)
  end

  test "reconcile_event_status reporté in array" do
    scraped_data = ["The Show Reporté","again"]
    expected_output = ["The Show Reporté - again", "EventStatusType", ["EventRescheduled", "http://schema.org/EventRescheduled"]]
    assert_equal expected_output, reconcile_event_status(scraped_data)
  end

  test "pipeline ok + missing yields extraction hint" do
    diagnosis = { status: :ok }
    hint = TracePresenter.new([]).diagnosis_relationship_hint(diagnosis, "missing")

    assert_match(/no data extracted/i, hint)
  end

  test "pipeline error + missing yields failure hint" do
    diagnosis = { status: :error }
    hint = TracePresenter.new([]).diagnosis_relationship_hint(diagnosis, "missing")

    assert_match(/pipeline failure/i, hint)
  end

  test "pipeline ok + problem yields content warning hint" do
    diagnosis = { status: :ok }
    hint = TracePresenter.new([]).diagnosis_relationship_hint(diagnosis, "problem")

    assert_match(/problematic/i, hint)
  end

  test "first empty step is detected" do
    steps = [
      { step: 1, output_full: ["a"], type: "xpath" },
      { step: 2, output_full: [], type: "xpath" }
    ]

    diagnosis = { status: :ok }

    hint = TracePresenter.new([]).diagnosis_relationship_hint(diagnosis, "missing", steps)

    assert_match(/step 2/i, hint)
  end

  test "freshness label for recent cache" do
    statement = OpenStruct.new(cache_refreshed: Time.current - 1800)
    label = cache_freshness_label(statement)

    assert_equal "fresh", label
  end

  test "freshness label for old cache" do
    statement = OpenStruct.new(cache_refreshed: Time.current - 40.days)
    label = cache_freshness_label(statement)

    assert_equal "stale", label
  end
end
