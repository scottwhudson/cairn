require "test_helper"

# The controller is now a thin HTTP shell over Debug::Session: it translates
# params into calls, and the session's answers into responses. These tests stub
# the session so no rdbg server is needed, and assert on that translation.
class DebugSessionsControllerTest < ActionDispatch::IntegrationTest
  SOURCE = Rails.root.join("app/services/debug/session.rb").to_s

  SNAPSHOT = {
    reason: "breakpoint",
    file: SOURCE,
    line: 10,
    frames: [{id: 11, name: "attach", file: SOURCE, line: 10, locals: []}],
    locals: []
  }.freeze

  class FakeClient
    attr_reader :host, :port, :snapshot, :state

    def initialize(snapshot: nil, state: :stopped)
      @host = "127.0.0.1"
      @port = 12345
      @snapshot = snapshot
      @state = state
    end

    def repo_path = Rails.root.to_s
  end

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

  # --- create ----------------------------------------------------------------

  test "attaching reports the target it connected to" do
    args = nil
    stub_session(:attach, ->(**kwargs) { args = kwargs; FakeClient.new }) do
      post debug_session_path, params: {debug_session: {host: "127.0.0.1", port: "12345"}}
    end

    assert_equal({host: "127.0.0.1", port: "12345"}, args)
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

  test "only host and port are permitted" do
    args = nil
    stub_session(:attach, ->(**kwargs) { args = kwargs; FakeClient.new }) do
      post debug_session_path, params: {debug_session: {port: "12345", repo_path: "/etc"}}
    end

    assert_equal %i[host port], args.keys
  end

  # --- step ------------------------------------------------------------------

  # Fire-and-forget: the resulting stop reaches the page over the stream.
  test "a step is accepted with no body" do
    command = nil
    stub_session(:step, ->(c) { command = c; true }) do
      post step_debug_session_path, params: {command: "step_in"}
    end

    assert_response :accepted
    assert_equal "step_in", command
    assert_empty response.body
  end

  test "a step the session refuses is unprocessable" do
    stub_session(:step, ->(_) { false }) { post step_debug_session_path, params: {command: "rewind"} }

    assert_response :unprocessable_entity
  end

  # --- select_frame ----------------------------------------------------------

  test "selecting a frame re-renders the three panels as turbo streams" do
    selected = nil
    panels = Debug::Panels.for(FakeClient.new, SNAPSHOT, frame_index: 0)

    stub_session(:panels, ->(frame:) { selected = frame; panels }) do
      post select_frame_debug_session_path, params: {frame: "1"}, as: :turbo_stream
    end

    assert_response :success
    assert_equal "1", selected
    assert_equal %w[source-panel callstack-panel locals-panel], turbo_streams.map { |s| s["target"] }
    assert_equal ["update"], turbo_streams.map { |s| s["action"] }.uniq
  end

  test "selecting a frame without a stop renders nothing" do
    stub_session(:panels, ->(frame:) { nil }) do
      post select_frame_debug_session_path, params: {frame: "0"}, as: :turbo_stream
    end

    assert_response :no_content
  end

  # --- expand_local ----------------------------------------------------------

  test "expanding a local streams its children into the row's container" do
    ref = nil
    children = [{name: "@name", value: '"ada"', type: "String", ref: 0}]

    stub_session(:expand, ->(r) { ref = r; children }) do
      post expand_local_debug_session_path, params: {ref: "42"}, as: :turbo_stream
    end

    assert_response :success
    assert_equal "42", ref
    stream = sole_turbo_stream
    assert_equal "var-children-42", stream["target"]
    assert_equal "update", stream["action"]
    assert_match(/@name/, response.body)
  end

  test "expanding a stale ref renders nothing" do
    stub_session(:expand, ->(_) { nil }) do
      post expand_local_debug_session_path, params: {ref: "42"}, as: :turbo_stream
    end

    assert_response :no_content
  end

  # --- evaluate --------------------------------------------------------------

  test "evaluating appends the expression and its result to the console" do
    args = nil
    result = {value: '"ada"', type: "String", ref: 0}

    stub_session(:evaluate, ->(expression, frame:) { args = [expression, frame]; result }) do
      post evaluate_debug_session_path, params: {expression: "  user.name  ", frame: "1"}, as: :turbo_stream
    end

    assert_response :success
    assert_equal ["user.name", "1"], args, "the expression is stripped before evaluating"
    stream = sole_turbo_stream
    assert_equal "repl-output", stream["target"]
    assert_equal "append", stream["action"]
    assert_match(/user\.name/, response.body)
  end

  test "an errored result is rendered without a var row" do
    result = {value: "undefined local variable", ref: 0, error: true}

    stub_session(:evaluate, ->(_, frame:) { result }) do
      post evaluate_debug_session_path, params: {expression: "nope", frame: "0"}, as: :turbo_stream
    end

    assert_response :success
    assert_match(/undefined local variable/, response.body)
  end

  test "an empty expression is never evaluated" do
    called = false
    stub_session(:evaluate, ->(*, **) { called = true }) do
      post evaluate_debug_session_path, params: {expression: "   "}, as: :turbo_stream
    end

    assert_response :no_content
    refute called
  end

  # --- destroy ---------------------------------------------------------------

  test "detaching leaves the debuggee running" do
    called = false
    stub_session(:detach, -> { called = true }) { delete debug_session_path }

    assert called
    assert_redirected_to root_path
    assert_equal "Detached. Your server keeps running.", flash[:notice]
  end

  private

  def stub_session(method, impl, &block) = stub_method(Debug::Session, method, impl, &block)

  def with_session(current:, &block) = stub_session(:current, -> { current }, &block)

  def turbo_streams = css_select("turbo-stream")

  def sole_turbo_stream
    assert_equal 1, turbo_streams.size
    turbo_streams.first
  end
end
