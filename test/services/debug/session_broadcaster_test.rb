require "test_helper"

class SessionBroadcasterTest < ViewComponent::TestCase
  FakeClient = Struct.new(:repo_path, :break_on_exception)

  Broadcast = Struct.new(:action, :stream, :target, :renderable)

  def setup
    @client = FakeClient.new("/repo", false)
    @broadcaster = Debug::SessionBroadcaster.new(@client)
    @snapshot = {reason: "breakpoint", frames: [{id: 1, name: "attach", file: "/repo/a.rb", line: 1, locals: []}]}
  end

  test "a stop repopulates the panels and reactivates the repl" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal %w[source-panel callstack-panel locals-panel repl-panel], sent.map(&:target)
    assert_includes render_inline(sent[1].renderable).to_html, "attach"
    assert_empty render_inline(sent.last.renderable).css("input[disabled]"), "the repl input is live at a stop"
  end

  # Each component renders its own id-bearing root, so a replace hands the id back.
  # There is no page-owned wrapper left that an update would have to preserve.
  test "every region is replaced rather than updated" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal [:replace], sent.map(&:action).uniq
  end

  test "the broadcaster names no dom ids of its own" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal sent.map { |b| b.renderable.id }, sent.map(&:target)
  end

  test "everything goes to the stream the show page subscribes to" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal ["debug_session"], sent.map(&:stream).uniq
  end

  [:running, :terminated].each do |state|
    test "#{state} blanks the panels and disables the repl" do
      sent = capture_broadcasts { @broadcaster.state_changed(state) }

      assert_equal %w[source-panel callstack-panel locals-panel], sent.first(3).map(&:target)
      assert_includes render_inline(sent[1].renderable).to_html, "No active frame"
      refute_empty render_inline(sent[3].renderable).css("input[disabled]"), "the repl input is dead once resumed"
    end
  end

  test "a state change always reports the new state to the status pill" do
    sent = capture_broadcasts { @broadcaster.state_changed(:running) }

    assert_equal "session-status", sent.last.target
    assert_includes render_inline(sent.last.renderable).to_html, "running"
  end

  # Stopping is the state that *has* a frame to show; blanking here would wipe
  # the panels the accompanying `stopped` event just filled.
  test "stopping updates only the status, leaving the panels alone" do
    sent = capture_broadcasts { @broadcaster.state_changed(:stopped) }

    assert_equal ["session-status"], sent.map(&:target)
  end

  test "an adapter error replaces the flash with the failed command" do
    sent = capture_broadcasts { @broadcaster.error("stepIn", "boom") }

    assert_equal [:replace], sent.map(&:action)
    assert_equal "session-flash", sent.sole.target
    assert_includes render_inline(sent.sole.renderable).to_html, "stepIn failed: boom"
  end

  private

  # Turbo broadcasts go out over ActionCable from the DapClient's dispatcher
  # thread; record them instead so we can assert on the frames themselves.
  def capture_broadcasts
    sent = []
    recorder = ->(action) {
      ->(stream, **opts) { sent << Broadcast.new(action, stream, opts[:target], opts[:renderable]) }
    }

    stub_method(Turbo::StreamsChannel, :broadcast_update_to, recorder.call(:update)) do
      stub_method(Turbo::StreamsChannel, :broadcast_replace_to, recorder.call(:replace)) do
        yield
      end
    end
    sent
  end
end
