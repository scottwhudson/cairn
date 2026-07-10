require "test_helper"

class DebugSessionsControllerTest < ActionDispatch::IntegrationTest
  include DebugSessionTestHelper

  # --- show ------------------------------------------------------------------

  test "shows an empty page when nothing is attached" do
    with_session(current: nil) { get root_path }

    assert_response :success
    assert_select "#source-panel"
    assert_select "#repl-panel", false
  end

  test "shows the current stop when attached" do
    with_session(current: FakeClient.new(snapshot: SNAPSHOT)) { get root_path }

    assert_response :success
    assert_select "#repl-panel"
  end

  # A Stimulus target only resolves inside its controller's element, and the repl
  # is rendered by a component the page nests rather than by the page itself.
  test "the repl log is a stepper target within the stepper's scope" do
    with_session(current: FakeClient.new(snapshot: SNAPSHOT)) { get root_path }

    assert_select "[data-controller='stepper'] [data-stepper-target='replOutput']"
  end

  # --- create ----------------------------------------------------------------

  test "attaching reports the target it connected to" do
    args = nil
    stub_session(:attach, ->(**kwargs) {
      args = kwargs
      FakeClient.new
    }) do
      post debug_session_path, params: {debug_session: {host: "127.0.0.1", port: "12345"}}
    end

    # repo_path is optional; the session defaults it when the form leaves it blank.
    assert_equal({host: "127.0.0.1", port: "12345", repo_path: nil}, args)
    assert_redirected_to root_path
    assert_equal "Attached to 127.0.0.1:12345. Trigger a request to hit the breakpoint.", flash[:notice]
  end

  test "attaching over a live session tells the user to disconnect first" do
    stub_session(:attach, ->(**) { raise Debug::Session::AlreadyAttached }) do
      post debug_session_path, params: {debug_session: {port: "12345"}}
    end

    assert_redirected_to root_path
    assert_equal "A session is already attached. Disconnect it first.", flash[:alert]
  end

  test "a failed attach surfaces the reason instead of a 500" do
    stub_session(:attach, ->(**) { raise Errno::ECONNREFUSED }) do
      post debug_session_path, params: {debug_session: {port: "12345"}}
    end

    assert_redirected_to root_path
    assert_match(/^Could not attach: Connection refused/, flash[:alert])
  end

  test "only the connect fields are permitted" do
    args = nil
    stub_session(:attach, ->(**kwargs) {
      args = kwargs
      FakeClient.new
    }) do
      post debug_session_path, params: {debug_session: {port: "12345", repo_path: "/etc", logger: "evil"}}
    end

    assert_equal %i[host port repo_path], args.keys
  end

  # --- destroy ---------------------------------------------------------------

  test "detaching leaves the debuggee running" do
    called = false
    stub_session(:detach, -> { called = true }) { delete debug_session_path }

    assert called
    assert_redirected_to root_path
    assert_equal "Detached. Your server keeps running.", flash[:notice]
  end
end
