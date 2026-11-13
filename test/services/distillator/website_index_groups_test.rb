require "test_helper"

class Distillator::WebsiteIndexGroupsTest < ActiveSupport::TestCase
  test "templates and manual French site are separate even if scheduled" do
    [site("01-event Template", "renamed-template", 1), site("Manual entry", "footlight-manual-fr", 1),
      site("Renamed", "2-fr-event", 0)].each do |website|
      assert_equal :templates, Distillator::WebsiteIndexGroups.category(website)
    end
  end

  test "test sites are separate while real venue names are not mistaken for tests" do
    [site("Code Snippet Test Site", "code-snippet-test", 1), site("Resource List", "testwebsite_RL-qa", nil)].each do |website|
      assert_equal :tests, Distillator::WebsiteIndexGroups.category(website)
    end
    assert_equal :scheduled, Distillator::WebsiteIndexGroups.category(site("Contest Theatre", "contest-theatre", 1))
  end

  test "place and people feeds include the retained Signe Laval feed but not Place des arts" do
    [site("Toronto Places", "nowplayingtoronto-com-places", 90), site("SPEC Artists", "spec-qc-ca-people", nil),
      site("Signé Laval (do NOT delete, keep places/people/orgs)", "signelaval-com", nil)].each do |website|
      assert_equal :entities, Distillator::WebsiteIndexGroups.category(website)
    end
    assert_equal :scheduled, Distillator::WebsiteIndexGroups.category(site("Place des arts", "placedesarts-com", 5))
  end

  test "schedule determines the current category without cached classification or duplicate membership" do
    website = site("Event venue", "event-venue", 1)
    assert_equal :scheduled, Distillator::WebsiteIndexGroups.category(website)
    [0, nil, -1].each do |days|
      website.schedule_every_days = days
      assert_equal :unscheduled, Distillator::WebsiteIndexGroups.category(website)
    end
    website.schedule_every_days = 7
    assert_equal :scheduled, Distillator::WebsiteIndexGroups.category(website)
    template = site("Template", "template", 0)
    groups = Distillator::WebsiteIndexGroups.call([website, template])
    assert_equal [website], groups[:scheduled]
    assert_equal [template], groups[:templates]
    assert_equal 2, groups.values.flatten.length
  end

  private

  def site(name, seedurl, days)
    Website.new(name: name, seedurl: seedurl, schedule_every_days: days)
  end
end
