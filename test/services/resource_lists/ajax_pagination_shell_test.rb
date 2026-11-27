# frozen_string_literal: true

require "minitest/autorun"
require "nokogiri"
require_relative "../../../app/services/resource_lists/ajax_pagination_shell"

class AjaxPaginationShellTest < Minitest::Test
  def inspect_html(html)
    ResourceLists::AjaxPaginationShell.inspect(Nokogiri::HTML(html))
  end

  def test_chasse_galerie_shell
    html = '<div class="events_container event_pagination_content_wrapper"></div>' +
      '<div data-pagination-ajax="/fetch-front-end-events"></div>'
    result = inspect_html(html)
    assert result.shell_only?
    assert_equal "/fetch-front-end-events", result.endpoint
  end

  def test_populated_event_container_not_shell_only
    html = '<div class="event_pagination_content_wrapper"><a href="/event/1">Event</a></div>' +
      '<div data-pagination-ajax="/fetch-front-end-events"></div>'
    refute inspect_html(html).shell_only?
  end

  def test_no_ajax_marker_not_shell_only
    refute inspect_html('<div class="event_pagination_content_wrapper"></div>').shell_only?
  end

  def test_missing_event_container_not_shell_only
    refute inspect_html('<div data-pagination-ajax="/fetch-front-end-events"></div>').shell_only?
  end

  def test_empty_ajax_endpoint_not_shell_only
    html = '<div class="event_pagination_content_wrapper"></div>' +
      '<div data-pagination-ajax=""></div>'
    refute inspect_html(html).shell_only?
  end
end
