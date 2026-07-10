require "test_helper"

class Debug::SelectedFramesControllerTest < ActionDispatch::IntegrationTest
  include DebugSessionTestHelper

  test "selecting a frame re-renders the three panels as turbo streams" do
    selected = nil
    panels = Debug::Panels.for(FakeClient.new, SNAPSHOT, frame_index: 0)

    stub_session(:panels, ->(frame:) {
      selected = frame
      panels
    }) do
      patch debug_session_selected_frame_path, params: {frame: "1"}, as: :turbo_stream
    end

    assert_response :success
    assert_equal "1", selected
    assert_equal %w[source-panel callstack-panel locals-panel], turbo_streams.map { |s| s["target"] }
    assert_equal ["replace"], turbo_streams.map { |s| s["action"] }.uniq
  end

  test "selecting a frame without a stop renders nothing" do
    stub_session(:panels, ->(frame:) {}) do
      patch debug_session_selected_frame_path, params: {frame: "0"}, as: :turbo_stream
    end

    assert_response :no_content
  end
end
