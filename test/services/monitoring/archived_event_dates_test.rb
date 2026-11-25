require "test_helper"

class ArchivedEventDatesTest < ActiveSupport::TestCase
  setup do
    @page = webpages(:six)
    @page.update_columns(url: "https://example.org/old-event", archive_date: Time.zone.local(2026, 10, 1))
    property = Property.create!(label: "Dates", uri: "urn:dates:monitor", rdfs_class: @page.rdfs_class, value_datatype: "xsd:dateTime")
    @source = Source.create!(website: @page.website, property: property, language: @page.language, selected: true,
      algorithm_value: "xpath=//time/@datetime")
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
  end

  test "reads a fresh date with explicit year without persisting statement or webpage changes" do
    now = Time.zone.local(2026, 11, 24, 12)
    html = '<time datetime="2027-01-15T20:00:00-05:00"></time><time datetime="December 5 at 20:00"></time>'
    Distillator::FreshWringerSnapshot.expects(:call).returns(status: "ok", payload: { "html" => html, "final_url" => @page.url })

    previous = @page.reload.attributes
    result = nil
    assert_no_difference "Statement.count" do
      result = Monitoring::ArchivedEventDates.call(@page, as_of: now)
    end
    assert_equal @source.id, result.source_id
    assert_equal Time.zone.local(2027, 1, 15, 20), result.date
    assert_equal previous, @page.reload.attributes
  end

  test "arbitrary Ruby is never evaluated and extra fetching is skipped" do
    @source.update!(algorithm_value: "xpath=//time/text(); ruby=raise 'unexpected'")
    Distillator::FreshWringerSnapshot.expects(:call).never
    result = Monitoring::ArchivedEventDates.call(@page)
    assert_equal "dates_extraction_requires_other_steps", result.reason
    assert_nil result.date
  end

  test "a redirect to a different event provides no evidence" do
    Distillator::FreshWringerSnapshot.expects(:call).returns(status: "ok",
      payload: { "html" => "<time>2030-12-25</time>", "final_url" => "https://different.example/event" })
    assert_equal "fresh_event_page_unavailable", Monitoring::ArchivedEventDates.call(@page).reason
  end
end
