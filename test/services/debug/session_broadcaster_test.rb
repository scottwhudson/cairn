require "test_helper"

class SessionBroadcasterTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:repo_path)

  Broadcast = Struct.new(:action, :stream, :target, :partial, :locals)

  def setup
    @client = FakeClient.new("/repo")
    @broadcaster = Debug::SessionBroadcaster.new(@client)
    @snapshot = {reason: "breakpoint", frames: [{id: 1}]}
  end

  test "a stop repopulates the panels and reactivates the repl" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal %w[source-panel callstack-panel locals-panel repl-panel], sent.map(&:target)
    assert_equal [@snapshot] * 3, sent.first(3).map { |b| b.locals[:snapshot] }
    assert_equal({stopped: true}, sent.last.locals)
  end

  # Panels must be *updated*, never replaced: replacing strips the id-bearing
  # wrapper, and the next broadcast silently no-ops against a missing target.
  test "panels are updated in place, so their wrapper ids survive" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal [:update], sent.map(&:action).uniq
  end

  test "everything goes to the stream the show page subscribes to" do
    sent = capture_broadcasts { @broadcaster.stopped(@snapshot) }

    assert_equal ["debug_session"], sent.map(&:stream).uniq
  end

  [:running, :terminated].each do |state|
    test "#{state} blanks the panels and disables the repl" do
      sent = capture_broadcasts { @broadcaster.state_changed(state) }

      panels = sent.first(3)
      assert_equal %w[source-panel callstack-panel locals-panel], panels.map(&:target)
      assert_equal [nil] * 3, panels.map { |b| b.locals[:snapshot] }
      assert_equal({stopped: false}, sent[3].locals)
    end
  end

  test "a state change always reports the new state to the status pill" do
    sent = capture_broadcasts { @broadcaster.state_changed(:running) }

    assert_equal "session-status", sent.last.target
    assert_equal({state: :running}, sent.last.locals)
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
    assert_equal({message: "stepIn failed: boom"}, sent.sole.locals)
  end

  private

  # Turbo broadcasts go out over ActionCable from the DapClient's dispatcher
  # thread; record them instead so we can assert on the frames themselves.
  def capture_broadcasts
    sent = []
    recorder = ->(action) {
      ->(stream, **opts) {
        sent << Broadcast.new(action, stream, opts[:target], opts[:partial], opts[:locals])
      }
    }

    stub_method(Turbo::StreamsChannel, :broadcast_update_to, recorder.call(:update)) do
      stub_method(Turbo::StreamsChannel, :broadcast_replace_to, recorder.call(:replace)) do
        yield
      end
    end
    sent
  end
end
