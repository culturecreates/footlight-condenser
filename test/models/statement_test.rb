require 'test_helper'

class StatementTest < ActiveSupport::TestCase
  def setup
    @statement = Statement.new(cache: '2020-05-23T13:30:00-04:00',
                               source: sources(:twelve))
  end

  test 'valid: date string' do
    assert @statement.valid_date?
  end

  test 'valid: array of dates with one good' do
    @statement.cache = "[\"2020-05-23T13:30:00-04:00\"]"
    assert @statement.valid_date?
  end

  test 'valid: array of dates with one good and one bad' do
    @statement.cache = "[\"2020-05-23T13:30:00-04:00\", \"error: missing date input\"]"
    assert @statement.valid_date?
  end

  test 'valid: array of dates with two good' do
    @statement.cache = "[\"2020-05-23T13:30:00-04:00\", \"2020-12-23T13:30:00-04:00\"]"
    assert @statement.valid_date?
  end

  test 'missing date' do
    @statement.cache = "[]"
    assert_not @statement.valid_date?
  end

  test 'invalid: array of dates with one bad' do
    @statement.cache = "[\"bad date input\"]"
    assert_not @statement.valid_date?
  end

  test 'invalid: array of dates with one error' do
    @statement.cache = "[\"error: missing date input\"]"
    assert_not @statement.valid_date?
  end

  test 'invalid: array of dates with two errors' do
    @statement.cache = "[\"error: missing date input\", \"error: missing another date input\"]"
    assert_not @statement.valid_date?
  end

  # valid_iso_date?
  test 'valid iso date' do
    assert @statement.valid_iso_date?('2020-05-23T13:30:00-04:00')
  end

  test 'invalid iso date' do
    assert_not @statement.valid_iso_date?('error')
  end

  test 'check_mandatory_properties no change' do
    @statement.status = 'updated'
    @statement.check_mandatory_properties
    assert_equal 'updated', @statement.status
  end
  
  test 'check_mandatory_properties bad date' do
    @statement.cache = "2020-05-23T"
    @statement.check_mandatory_properties
    assert_equal 'missing', @statement.status

  end

  test 'check_no_abort_update detected' do
    @statement.cache = "long message with abort_update."
    @statement.check_no_abort_update
    assert_equal 'problem', @statement.status
  end

  test 'check_no_abort_update not present' do
    @statement.cache = "long message looking good."
    @statement.check_no_abort_update
    assert_nil  @statement.status
  end

  test 'check_no_abort_update not in array' do
    @statement.cache = ["array"]
    @statement.check_no_abort_update
    assert_nil @statement.status
  end

  test 'check_no_abort_update in array' do
    @statement.cache = ["array","abort_update"]
    @statement.check_no_abort_update
    assert_equal 'problem', @statement.status
  end

  # check_for_invalid_price
  test 'check_for_invalid_price' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "123.50"
    @statement.check_for_invalid_price
    assert_nil @statement.status
  end

  test 'check_for_invalid_price NaN' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = 'NaN'  
    @statement.check_for_invalid_price
    assert_equal 'problem', @statement.status
  end

  test 'check_for_invalid_price with comma' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "12,3"
    @statement.check_for_invalid_price
    assert_equal 'problem', @statement.status
  end

  test 'check_for_invalid_price with array of float and integer prices' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "[42.0, 38, 38.4]"
    @statement.check_for_invalid_price
    assert_nil  @statement.status
  end
 
  test 'check_for_invalid_price with array with an invalid price' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "[42.0, \"NaN\", 38.4]"
    @statement.check_for_invalid_price
    assert_equal 'problem', @statement.status
  end

  test 'check_for_invalid_price with array of string prices' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "[42.0, \"38\", \"38.4\"]"
    @statement.check_for_invalid_price
    assert_nil  @statement.status
  end

  # This test is when the second ticket is out of stock, 
  # and the position needs to be maintained with a blank,
  # in order to align the price array with the availability array.
  test 'check_for_invalid_price with array of string and null string' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "[\"42\", \"\", \"38.4\"]"
    @statement.check_for_invalid_price
    assert_nil  @statement.status
  end

  test 'ensure we have an array' do
    assert_equal ["one"], @statement.convert_array("[\"one\"]")
  end

  test 'ensure we have an array from single number' do
    assert_equal [23], @statement.convert_array("23")
  end

  test 'ensure we have an array from array of floats as strings' do
    assert_equal [23.5,28], @statement.convert_array("[23.5,28]")
  end
  
  test 'ensure we have an array from array of floats' do
    assert_equal [23.5,28], @statement.convert_array([23.5,28])
  end
end
