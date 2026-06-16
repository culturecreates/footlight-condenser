require "test_helper"

class Dsl::Identity::UrlIdentifierTest < ActiveSupport::TestCase
  test "extracts id from /events/:id" do
    url = "http://site.com/events/abc123"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "abc123", result
  end

  test "extracts id from /billets/:id" do
    url = "http://site.com/billets/mti260327001"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "mti260327001", result
  end

  test "extracts id from /tickets/:id" do
    url = "http://site.com/tickets/999"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "999", result
  end

  test "avoids trailing segments" do
    url = "http://site.com/events/123/details"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "123", result
  end

  test "avoids generic segments" do
    url = "http://site.com/events/show"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_not_equal "show", result
  end

  test "extracts slug without digits" do
    url = "http://site.com/events/festival-jazz"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "festival-jazz", result
  end

  test "avoids event generic segment" do
    url = "http://site.com/events/event"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_not_equal "event", result
  end

  test "keeps mixed case slug before normalization" do
    url = "http://site.com/events/Festival-Jazz"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "Festival-Jazz", result
  end

  test "fallback still works for short path segments" do
    url = "http://site.com/a/b/"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "b", result
  end

  test "extracts lepointdevente billets id" do
    url = "https://lepointdevente.com/billets/mti260327001"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "mti260327001", result
  end

  test "extracts eventbrite trailing numeric id" do
    url = "https://www.eventbrite.com/e/my-event-name-tickets-123456789"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "123456789", result
  end

  test "extracts ticketweb last numeric segment" do
    url = "https://www.ticketweb.ca/event/foo/14122674"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "14122674", result
  end

  test "lepointdevente billets empty match is not empty" do
    url = "https://lepointdevente.com/billets/"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_not_equal "", result.to_s
  end

  test "eventbrite extracts id with trailing characters" do
    url = "https://eventbrite.com/e/foo-123456789-extra"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_equal "123456789", result
  end

  test "not eventbrite domain does not use eventbrite extraction" do
    url = "https://not-eventbrite.com/e/foo-123456789"

    result = Dsl::Identity::UrlIdentifier.call(url)

    assert_not_equal "123456789", result
  end
end
