require "test_helper"

class Debug::LocalsControllerTest < ActionDispatch::IntegrationTest
  include DebugSessionTestHelper

  test "expanding a local streams its children into the row's container" do
    ref = nil
    children = [{name: "@name", value: '"ada"', type: "String", ref: 0}]

    stub_session(:expand, ->(r) {
      ref = r
      children
    }) do
      get debug_session_local_path(42), as: :turbo_stream
    end

    assert_response :success
    assert_equal "42", ref
    stream = sole_turbo_stream
    assert_equal "var-children-42", stream["target"]
    assert_equal "update", stream["action"]
    assert_match(/@name/, response.body)
  end

  # A structured child is drillable in turn, and carries the URL its own
  # expansion will GET — built by the route helper rather than assembled in JS.
  test "a structured child carries the url that expands it" do
    children = [{name: "@tags", value: "[...]", type: "Array", ref: 7}]

    stub_session(:expand, ->(_) { children }) do
      get debug_session_local_path(42), as: :turbo_stream
    end

    assert_response :success
    assert_select "button[data-stepper-url-param=?]", debug_session_local_path(7)
  end

  test "expanding a stale ref renders nothing" do
    stub_session(:expand, ->(_) {}) do
      get debug_session_local_path(42), as: :turbo_stream
    end

    assert_response :no_content
  end
end
