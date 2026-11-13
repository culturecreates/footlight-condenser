require "test_helper"

class Distillator::FetchCacheTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
  end

  test "requires unique uri_key" do
    Distillator::FetchCache.create!(uri_key: "http%3A%2F%2Fexample.com", normalized_url: "http://example.com")
    duplicate = Distillator::FetchCache.new(uri_key: "http%3A%2F%2Fexample.com", normalized_url: "http://example.com")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:uri_key], "has already been taken"
  end
end
