require "test_helper"

class HarmonizedCardPartialRenderingTest < ActiveSupport::TestCase
  test "card grid escapes text by default" do
    html = ApplicationController.render(
      partial: "shared/cards/card_grid",
      locals: {
        cards: [
          {
            title: "Unsafe card",
            rows: [{ label: "Body", value: "<em>unsafe</em>" }]
          }
        ]
      }
    )

    assert_includes html, "&lt;em&gt;unsafe&lt;/em&gt;"
    refute_includes html, "<em>unsafe</em>"
  end

  test "card grid renders HTML only when explicitly marked html true" do
    html = ApplicationController.render(
      partial: "shared/cards/card_grid",
      locals: {
        cards: [
          {
            title: "Trusted card",
            rows: [{ label: "Body", value: "<em>trusted</em>", html: true }]
          }
        ]
      }
    )

    assert_includes html, "<em>trusted</em>"
  end

  test "action bar handles empty action groups" do
    html = ApplicationController.render(
      partial: "shared/cards/action_bar",
      locals: { groups: [] }
    )

    assert_includes html, "harmonized-card-actions"
    refute_includes html, "cache-action-group"
  end
end
