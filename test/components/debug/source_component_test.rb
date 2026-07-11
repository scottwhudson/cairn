require "test_helper"

# The center panel shows source at the selected frame. It has to cope with a nil
# snapshot (detached), a frame whose file it can't read, and an exception stop that
# wants the raise called out. It reads whatever frame_index it's handed — Session
# has already clamped it to the stack.
class Debug::SourceComponentTest < ViewComponent::TestCase
  REPO = Rails.root.to_s
  SOURCE = Rails.root.join("app/services/debug/session.rb").to_s

  def frame(file: SOURCE, line: 10, name: "attach")
    {id: 1, name: name, file: file, line: line}
  end

  def snapshot(reason: "breakpoint", frames: [frame], **extra)
    {reason: reason, frames: frames, **extra}
  end

  test "with no snapshot it invites you to attach" do
    panel = render_inline Debug::SourceComponent.new(snapshot: nil, repo_path: REPO)

    assert_includes panel.to_html, "No source yet"
    assert_includes panel.to_html, "Not attached"
  end

  test "the selected frame's file is read and shown relative to the repo" do
    panel = render_inline Debug::SourceComponent.new(snapshot: snapshot, repo_path: REPO)

    assert_includes panel.to_html, "app/services/debug/session.rb:10"
    assert panel.css("pre").any?, "expected the source to render"
  end

  # frame_index picks which frame drives the pane; Session clamps it, so the panel
  # just trusts it.
  test "a non-zero frame index drives which frame is shown" do
    frames = [frame(line: 10), frame(line: 20)]
    panel = render_inline Debug::SourceComponent.new(snapshot: snapshot(frames: frames), repo_path: REPO, frame_index: 1)

    assert_includes panel.to_html, "session.rb:20"
  end

  # A snapshot can carry a top-level file/line with no frames (an early stop); the
  # pane falls back to those.
  test "it falls back to the snapshot's own file and line when there are no frames" do
    snap = {reason: "breakpoint", frames: nil, file: SOURCE, line: 5}
    panel = render_inline Debug::SourceComponent.new(snapshot: snap, repo_path: REPO)

    assert_includes panel.to_html, "session.rb:5"
  end

  test "a file it cannot read reports that instead of blanking" do
    snap = snapshot(frames: [frame(file: "/no/such/file.rb", line: 1)])
    panel = render_inline Debug::SourceComponent.new(snapshot: snap, repo_path: REPO)

    assert_includes panel.to_html, "Could not read"
  end

  test "the stop reason is shown as a pill" do
    panel = render_inline Debug::SourceComponent.new(snapshot: snapshot(reason: "step"), repo_path: REPO)

    assert_includes panel.to_html, "step"
  end

  # An exception stop is colored apart and surfaces rdbg's description of the raise.
  test "an exception stop reads rose and names the exception" do
    snap = snapshot(reason: "exception", exception: "RuntimeError: boom")
    panel = render_inline Debug::SourceComponent.new(snapshot: snap, repo_path: REPO)

    assert_includes panel.to_html, "RuntimeError: boom"
    assert_includes panel.to_html, "rose"
  end

  test "a breakpoint stop does not read as an exception" do
    panel = render_inline Debug::SourceComponent.new(snapshot: snapshot, repo_path: REPO)

    assert_not_includes panel.to_html, "rose-500/20"
  end

  test "the panel renders the id the broadcaster replaces" do
    panel = render_inline Debug::SourceComponent.new(snapshot: snapshot, repo_path: REPO)

    assert_equal "source-panel", Debug::SourceComponent::ID
    assert panel.css("##{Debug::SourceComponent::ID}").any?
  end
end
