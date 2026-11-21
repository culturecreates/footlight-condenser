module HarmonizedCardAssertions
  def assert_harmonized_record_card(section_selector: "section.cache-detail-cards")
    assert_select section_selector, 1
    assert_select "#{section_selector} article.cache-detail-card", minimum: 1
  end

  def assert_harmonized_card_action_bar(action_selector: ".cache-actions")
    assert_select action_selector, minimum: 1
    assert_select "#{action_selector} .cache-action-group strong", text: "View"
    assert_select "#{action_selector} a", text: "Show"
    assert_select "#{action_selector} a", text: "Raw"
    assert_select "#{action_selector} a", text: ".json"
    assert_select "#{action_selector} a", text: "Pretty JSON"
    assert_select "#{action_selector} a", text: "Compare"
  end
end

ActiveSupport::TestCase.include(HarmonizedCardAssertions)
