require "test_helper"

class Debug::StepsControllerTest < ActionDispatch::IntegrationTest
  include DebugSessionTestHelper

  # Fire-and-forget: the resulting stop reaches the page over the stream.
  test "a step is accepted with no body" do
    command = nil
    stub_session(:step, ->(c) {
      command = c
      true
    }) do
      post debug_session_steps_path, params: {command: "step_in"}
    end

    assert_response :accepted
    assert_equal "step_in", command
    assert_empty response.body
  end

  test "a step the session refuses is unprocessable" do
    stub_session(:step, ->(_) { false }) { post debug_session_steps_path, params: {command: "rewind"} }

    assert_response :unprocessable_entity
  end
end
