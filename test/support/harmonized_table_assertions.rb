module HarmonizedTableAssertions
  def assert_harmonized_table_shell
    assert_select ".harmonized-table-shell", 1
  end

  def assert_harmonized_filter_form(action:)
    assert_select %(form[action="#{action}"][method="get"]), 1
  end

  def assert_harmonized_filter_shell(form_action: "/distillator/cache", details_selector: "details.cache-advanced-filters")
    assert_harmonized_filter_form(action: form_action)
    assert_select %(form[action="#{form_action}"][method="get"]), 1
    assert_select details_selector, 1
  end

  def assert_harmonized_advanced_filters(details_selector: "details.cache-advanced-filters")
    assert_select "#{details_selector} summary", text: "Advanced filters"
    assert_select "#{details_selector} input[name='term']", 1
    assert_select "#{details_selector} select[name='health']", 1
    assert_select "#{details_selector} input[name='http_response_code']", 1
    assert_select "#{details_selector} select[name='status_group']", 1
    assert_select "#{details_selector} select[name='has_html']", 1
    assert_select "#{details_selector} input[name='network_status']", 1
    assert_select "#{details_selector} select[name='content_type']", 1
    assert_select "#{details_selector} select[name='redirected']", 1
    assert_select "#{details_selector} input[name='hint']", 1
    assert_select "#{details_selector} select[name='last_attempt']", 1
    assert_select "#{details_selector} select[name='last_success']", 1
  end

  def assert_harmonized_sortable_header(label:, sort_key:)
    assert_select %(th a[href*="sort=#{sort_key}"]), text: /#{Regexp.escape(label)}/
  end

  def assert_harmonized_reset_filters_link(path: "/distillator/cache", params: {})
    href = build_expected_href(path, params)
    assert_select %(a[href="#{href}"]), text: "Reset filters"
  end

  def assert_harmonized_apply_filters_button
    assert_select %(input[type="submit"][value="Apply filters"]), 1
  end

  def assert_harmonized_summary_cards_before_filters(summary_text: "Healthy", filter_text: "Advanced filters")
    assert_operator @response.body.index(summary_text), :<, @response.body.index(filter_text)
  end

  def assert_sort_link_preserves_filters(label:, sort_key:, params:)
    href = sortable_header_href(label: label, sort_key: sort_key)
    params.each do |key, value|
      assert_includes href, "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
    end
    assert_no_match(/(?:\?|&)page=/, href)
  end

  def assert_sort_link_preserves_params(label:, sort_key:, params:)
    href = sortable_header_href(label: label, sort_key: sort_key)
    params.each do |key, value|
      assert_includes href, "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
    end
  end

  private

  def sortable_header_href(label:, sort_key:)
    document = Nokogiri::HTML(@response.body)
    link = document.css("th a").find do |node|
      node.text.include?(label) && node["href"].to_s.include?("sort=#{sort_key}")
    end
    assert link, "Expected sortable header #{label.inspect} for #{sort_key.inspect}"
    link["href"]
  end

  def build_expected_href(path, params)
    query = params.compact_blank.to_query
    query.present? ? "#{path}?#{query}" : path
  end
end

ActiveSupport::TestCase.include(HarmonizedTableAssertions)
