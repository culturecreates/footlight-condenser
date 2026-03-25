require "test_helper"

class TracePresenterTest < ActiveSupport::TestCase
  test "trace_presenter detects errors" do
    presenter = TracePresenter.new([
      { error: "boom" }
    ])

    assert presenter.has_error?
  end

  test "trace_presenter returns steps from hash trace" do
    presenter = TracePresenter.new({ steps: [{ step: 1 }] })

    assert_equal 1, presenter.steps.size
  end

  test "visible? returns true when always" do
    presenter = TracePresenter.new([])
    cookies = { trace_visibility: "always" }

    assert presenter.visible?(cookies)
  end

  test "visible? returns false when hidden" do
    presenter = TracePresenter.new([])
    cookies = { trace_visibility: "hidden" }

    refute presenter.visible?(cookies)
  end

  test "visible? uses has_error? when auto" do
    presenter = TracePresenter.new([{ error: "boom" }])
    cookies = { trace_visibility: "auto" }

    assert presenter.visible?(cookies)
  end

  test "mode defaults to 3" do
    presenter = TracePresenter.new([])
    cookies = {}

    assert_equal 3, presenter.mode(cookies)
  end

  test "mode reads from cookies" do
    presenter = TracePresenter.new([])
    cookies = { trace_view_mode: "2" }

    assert_equal 2, presenter.mode(cookies)
  end

  test "mode falls back when invalid value" do
    presenter = TracePresenter.new([])
    cookies = { trace_view_mode: "999" }

    assert_equal 3, presenter.mode(cookies)
  end

  test "visibility is case insensitive" do
    presenter = TracePresenter.new([])
    cookies = { trace_visibility: "ALWAYS" }

    assert presenter.visible?(cookies)
  end
end
