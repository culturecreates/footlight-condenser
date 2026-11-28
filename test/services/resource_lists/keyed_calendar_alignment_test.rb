require "test_helper"

module ResourceLists
  class KeyedCalendarAlignmentTest < ActiveSupport::TestCase
    # Pure keyed calendar tests must not load unrelated database fixtures.
    self.fixture_table_names = []

    test "languages align by key even when source order differs" do
      result = KeyedCalendarAlignment.call(streams: {
        fr: [{key: "C", url: "/fr/c"}, {key: "A", url: "/fr/a"}, {key: "B", url: "/fr/b"}],
        en: [{key: "B", url: "/en/b"}, {key: "C", url: "/en/c"}, {key: "A", url: "/en/a"}]
      })
      assert result.complete?
      assert_equal %w[A B C], result.pairs.map(&:key)
      assert_equal %w[/fr/a /fr/b /fr/c], result.paired_urls_for(:fr)
      assert_equal %w[/en/a /en/b /en/c], result.paired_urls_for(:en)
    end

    test "Meridian cached ResourceLists keep Christmas Carol and Jersey Nights paired despite swapped positions and duplicate URLs" do
      # The selected EN/FR URL/URI lists on QA Website #585 (2026-11-28)
      # differ at positions 5 and 6. Both also repeat later-page URLs.
      # This is a concrete regression against cross-language array zipping.
      keys = %w[christmas-carol-solo-performed-pierre-brault jersey-nights-before-christmas hotel-california]
      en = [keys[0], keys[1], keys[2], keys[2]].map { |key| { key: key, url: "https://meridiancentrepointe.com/en/#{key}" } }
      fr = [keys[1], keys[0], keys[2], keys[2]].map { |key| { key: key, url: "https://meridiancentrepointe.com/fr/#{key}" } }
      result = KeyedCalendarAlignment.call(streams: { en: en, fr: fr })
      assert result.complete?, result.errors.inspect
      assert_equal keys.sort, result.pairs.map(&:key)
      result.pairs.each do |pair|
        assert_equal pair.urls.fetch(:en).sub("/en/", "/fr/"), pair.urls.fetch(:fr)
      end
      assert_equal 3, result.pairs.length
    end

    test "unmatched translations cannot be exported as aligned arrays" do
      result = KeyedCalendarAlignment.call(streams: {
        fr: [{key: "A", url: "/fr/a"}, {key: "B", url: "/fr/b"}],
        en: [{key: "A", url: "/en/a"}]
      })
      assert_equal "incomplete", result.status
      assert_equal ["B"], result.unmatched.map(&:key)
      assert_raises(ArgumentError) { result.paired_urls_for(:fr) }
    end

    test "duplicate key with conflicting URLs must never silently overwrite" do
      result = KeyedCalendarAlignment.call(streams: {
        fr: [{key: "A", url: "/fr/a"}, {key: "A", url: "/fr/other"}],
        en: [{key: "A", url: "/en/a"}]
      })
      assert_equal "invalid", result.status
      assert_includes result.errors, "duplicate_key: fr:A"
    end

    test "same URL and key repeated on adjacent pages is safe" do
      result = KeyedCalendarAlignment.call(streams: {fr: [{key: "A", url: "/fr/a"}, {key: "A", url: "/fr/a"}]})
      assert result.complete?
      assert_equal ["/fr/a"], result.paired_urls_for(:fr)
    end

    test "different keys for same URL are rejected" do
      result = KeyedCalendarAlignment.call(streams: {en: [{key: "A", url: "/en/x"}, {key: "B", url: "/en/x"}]})
      assert_equal "invalid", result.status
      assert result.errors.any? { |error| error.start_with?("conflicting_keys_for_url:") }
    end

    test "stable digest does not depend on discovery ordering" do
      one = KeyedCalendarAlignment.call(streams: {en: [{key: "2", url: "/en/2"}, {key: "1", url: "/en/1"}], fr: [{key: "1", url: "/fr/1"}, {key: "2", url: "/fr/2"}]})
      two = KeyedCalendarAlignment.call(streams: {fr: [{key: "2", url: "/fr/2"}, {key: "1", url: "/fr/1"}], en: [{key: "1", url: "/en/1"}, {key: "2", url: "/en/2"}]})
      assert_equal one.digest, two.digest
    end
  end
end
