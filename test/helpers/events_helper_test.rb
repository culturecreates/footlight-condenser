require 'test_helper'

class EventsHelperTest < ActionView::TestCase


  test "Convert Str to first Date" do
    expected_output = DateTime.parse("Wed, 06 May 2020 19:30:00 -0400")
    assert_equal expected_output, parse_date_string_array("2020-05-06T19:30:00-04:00")
  end


  test "Convert Stringified Array of dates to first Date" do
    expected_output = DateTime.parse("Sat, 16 Nov 2019 21:00:00 -0500")
    assert_equal expected_output, parse_date_string_array("[\"2019-11-16T21:00:00-05:00\", \"2019-11-16T23:30:00-05:00\"]")
  end

  test "Convert error string to future Date" do
    expected_output = DateTime.now + 1.year
    assert_equal expected_output.to_i, parse_date_string_array("[\"Error scrapping\"]").to_i
  end


  test "Choose non-error string to get valid date" do
    expected_output = DateTime.parse("Sat, 16 Nov 2019 21:00:00 -0500")
    assert_equal expected_output.to_i, parse_date_string_array("[\"Error scrapping\",\"2019-11-16T21:00:00-05:00\"]").to_i
  end
  

end
