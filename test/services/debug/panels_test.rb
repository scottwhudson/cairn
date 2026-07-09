require "test_helper"

class PanelsTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:repo_path)

  def setup
    @client = FakeClient.new("/repo")
    @snapshot = {reason: "breakpoint", frames: [{id: 1}, {id: 2}]}
  end

  test "builds one panel per target, in render order" do
    panels = Debug::Panels.for(@client, @snapshot)

    assert_equal %w[source-panel callstack-panel locals-panel], panels.map(&:target)
    assert_equal %w[debug_sessions/source debug_sessions/callstack debug_sessions/locals],
      panels.map(&:partial)
  end

  test "every panel gets the snapshot, repo path and frame index" do
    panels = Debug::Panels.for(@client, @snapshot, frame_index: 1)

    panels.each do |panel|
      assert_equal({repo_path: "/repo", snapshot: @snapshot, frame_index: 1}, panel.locals)
    end
  end

  test "defaults to the top frame" do
    assert_equal 0, Debug::Panels.for(@client, @snapshot).first.locals[:frame_index]
  end

  # A nil snapshot is how the broadcaster blanks the panels on resume.
  test "a nil snapshot still yields every panel, with no snapshot to render" do
    panels = Debug::Panels.for(@client, nil)

    assert_equal 3, panels.size
    assert_nil panels.first.locals[:snapshot]
  end

  test "tolerates a detached session with no client" do
    assert_nil Debug::Panels.for(nil, nil).first.locals[:repo_path]
  end
end
