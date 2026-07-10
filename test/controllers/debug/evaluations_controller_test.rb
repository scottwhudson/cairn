require "test_helper"

class Debug::EvaluationsControllerTest < ActionDispatch::IntegrationTest
  include DebugSessionTestHelper

  test "evaluating appends the expression and its result to the console" do
    args = nil
    result = {value: '"ada"', type: "String", ref: 0}

    stub_session(:evaluate, ->(expression, frame:) {
      args = [expression, frame]
      result
    }) do
      post debug_session_evaluations_path, params: {expression: "  user.name  ", frame: "1"}, as: :turbo_stream
    end

    assert_response :success
    assert_equal ["user.name", "1"], args, "the expression is stripped before evaluating"
    stream = sole_turbo_stream
    assert_equal "repl-output", stream["target"]
    assert_equal "append", stream["action"]
    # Rouge splits the echoed expression across highlighting spans, so match on
    # the element's text rather than the raw body.
    assert_select "code", text: "user.name"
  end

  test "an errored result is rendered without a var row" do
    result = {value: "undefined local variable", ref: 0, error: true}

    stub_session(:evaluate, ->(_, frame:) { result }) do
      post debug_session_evaluations_path, params: {expression: "nope", frame: "0"}, as: :turbo_stream
    end

    assert_response :success
    assert_match(/undefined local variable/, response.body)
  end

  test "an empty expression is never evaluated" do
    called = false
    stub_session(:evaluate, ->(*, **) { called = true }) do
      post debug_session_evaluations_path, params: {expression: "   "}, as: :turbo_stream
    end

    assert_response :no_content
    refute called
  end
end
