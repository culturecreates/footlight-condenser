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


end
