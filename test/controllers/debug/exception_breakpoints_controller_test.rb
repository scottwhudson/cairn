require "test_helper"

class Debug::ExceptionBreakpointsControllerTest < ActionDispatch::IntegrationTest
  include DebugSessionTestHelper

  test "arming stops the debuggee at a raise" do
    enabled = nil
    with_attached_session(FakeClient.new(state: :running)) do
      stub_session(:break_on_exception, ->(e) { enabled = e }) do
        post debug_session_exception_breakpoint_path, as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal true, enabled
  end

  test "disarming lets the debuggee unwind to its own error page" do
    enabled = nil
    with_attached_session(FakeClient.new(state: :running, break_on_exception: true)) do
      stub_session(:break_on_exception, ->(e) { enabled = e }) do
        delete debug_session_exception_breakpoint_path, as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal false, enabled
  end

  # The toggle has to show what the adapter accepted, not what was clicked.
  test "toggling re-renders the status region" do
    with_attached_session(FakeClient.new(state: :running)) do
      stub_session(:break_on_exception, ->(_) {}) do
        post debug_session_exception_breakpoint_path, as: :turbo_stream
      end
    end

    stream = sole_turbo_stream
    assert_equal "session-status", stream["target"]
    assert_equal "replace", stream["action"]
  end

  # Armed, the button offers the disarm; the verb carries the state.
  test "an armed breakpoint renders its toggle as a delete" do
    with_attached_session(FakeClient.new(state: :running, break_on_exception: true)) do
      stub_session(:break_on_exception, ->(_) {}) do
        post debug_session_exception_breakpoint_path, as: :turbo_stream
      end
    end

    assert_match(/name="_method" value="delete"/, response.body)
  end

  test "an adapter that refuses surfaces the reason in the flash" do
    with_attached_session(FakeClient.new(state: :running)) do
      stub_session(:break_on_exception, ->(_) { raise Debug::DapClient::Error, "no catchpoints" }) do
        post debug_session_exception_breakpoint_path, as: :turbo_stream
      end
    end

    assert_response :success
    stream = sole_turbo_stream
    assert_equal "session-flash", stream["target"]
    assert_equal "replace", stream["action"]
    assert_match(/Could not arm exception breakpoint: no catchpoints/, response.body)
  end

  test "toggling without a session is unprocessable" do
    with_session(current: nil) { post debug_session_exception_breakpoint_path, as: :turbo_stream }

    assert_response :unprocessable_entity
  end
end
