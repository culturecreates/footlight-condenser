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
    expected = 'updated'
    @statement.check_mandatory_properties
    assert_equal expected, @statement.status
  end
  
  test 'check_mandatory_properties bad date' do
    @statement.cache = "2020-05-23T"
    @statement.check_mandatory_properties
    expected = 'missing'
    assert_equal expected, @statement.status

  end

  test 'check_no_abort_update detected' do
    @statement.cache = "long message with abort_update."
    @statement.check_no_abort_update
    expected = 'problem'
    assert_equal expected, @statement.status
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
    expected = 'problem'
    assert_equal expected, @statement.status
  end

  test 'check_for_invalid_price' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = '123.50'
    @statement.check_for_invalid_price
   
    assert_nil @statement.status
  end

  test 'check_for_invalid_price NaN' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = 'NaN'  
    @statement.check_for_invalid_price
    expected = 'problem'
    assert_equal expected, @statement.status
  end

  test 'check_for_invalid_price with comma' do
    @statement = Statement.new(source: sources(:priceSource))
    @statement.cache = "12,3"
    @statement.check_for_invalid_price
    expected = 'problem'
    assert_equal expected, @statement.status
  end



end
