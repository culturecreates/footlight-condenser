require "test_helper"

class OptionsControllerTest < ActionDispatch::IntegrationTest
  test "options page shows cache link in internal navigation" do
    get options_path

    assert_response :success
    assert_match '/distillator/cache', @response.body
    assert_match '>cache<', @response.body
  end

  test "set_trace_view_mode stores cookie and redirects back" do
    post set_trace_view_mode_path(2), headers: { "HTTP_REFERER" => options_url }

    assert_redirected_to options_url
    assert_equal "2", cookies[:trace_view_mode]
  end
end
