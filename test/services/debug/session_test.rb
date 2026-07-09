require "test_helper"

class SessionTest < ActiveSupport::TestCase
  # Stands in for a DapClient attached to an rdbg server, recording the execution
  # commands Session drives it with.
  class FakeClient
    attr_reader :repo_path, :state, :snapshot, :commands, :evaluated, :expanded

    def initialize(state: :stopped, snapshot: nil)
      @repo_path = "/repo"
      @state = state
      @snapshot = snapshot
      @commands = []
      @detached = false
    end

    %i[continue step_over step_in step_out].each do |command|
      define_method(command) { @commands << command }
    end

    def evaluate(expression, frame_id:) = (@evaluated = {expression: expression, frame_id: frame_id})

    def expand(ref) = (@expanded = ref) && [{name: "@a", value: "1"}]

    def detach = (@detached = true)

    def detached? = @detached
  end

  SNAPSHOT = {
    reason: "breakpoint",
    frames: [{id: 11, name: "top"}, {id: 22, name: "caller"}]
  }.freeze

  def teardown
    Debug::SessionRegistry.clear
  end

  def attach(client)
    Debug::SessionRegistry.put(client)
    client
  end

  # --- lifecycle -------------------------------------------------------------

  test "no session is attached by default" do
    assert_nil Debug::Session.current
    refute Debug::Session.attached?
  end

  test "current exposes the attached client" do
    client = attach(FakeClient.new)

    assert_same client, Debug::Session.current
    assert Debug::Session.attached?
  end

  test "attaching over a live session is refused" do
    attach(FakeClient.new)

    assert_raises(Debug::Session::AlreadyAttached) do
      Debug::Session.attach(host: "127.0.0.1", port: "1234")
    end
  end

  test "detaching disconnects the client and empties the registry" do
    client = attach(FakeClient.new)

    Debug::Session.detach

    assert client.detached?
    refute Debug::Session.attached?
  end

  test "detaching without a session is a no-op" do
    assert_nothing_raised { Debug::Session.detach }
  end

  # The debuggee going away must clear the registry, or the next attach is refused
  # for a session that no longer exists.
  test "the debuggee terminating clears the registry" do
    client = Debug::DapClient.new(host: "127.0.0.1", port: 1234)
    Debug::Session.send(:wire_callbacks, client)
    attach(client)

    silence_broadcasts { client.send(:transition, :terminated) }

    refute Debug::Session.attached?
  end

  # --- stepping --------------------------------------------------------------

  {"continue" => :continue, "next" => :step_over,
   "step_in" => :step_in, "step_out" => :step_out}.each do |command, method|
    test "#{command.inspect} drives the client's #{method}" do
      client = attach(FakeClient.new)

      assert Debug::Session.step(command)
      assert_equal [method], client.commands
    end
  end

  test "an unknown command drives nothing" do
    client = attach(FakeClient.new)

    refute Debug::Session.step("rewind")
    assert_empty client.commands
  end

  test "stepping without a session drives nothing" do
    refute Debug::Session.step("continue")
  end

  # --- panels ----------------------------------------------------------------

  test "panels focus the requested frame of the current stop" do
    attach(FakeClient.new(snapshot: SNAPSHOT))

    assert_equal 1, Debug::Session.panels(frame: "1").first.locals[:frame_index]
  end

  test "a frame beyond the stack clamps to the deepest one" do
    attach(FakeClient.new(snapshot: SNAPSHOT))

    assert_equal 1, Debug::Session.panels(frame: "99").first.locals[:frame_index]
  end

  test "a negative frame clamps to the top of the stack" do
    attach(FakeClient.new(snapshot: SNAPSHOT))

    assert_equal 0, Debug::Session.panels(frame: "-3").first.locals[:frame_index]
  end

  test "a frameless stop clamps to zero rather than to -1" do
    attach(FakeClient.new(snapshot: {reason: "breakpoint", frames: []}))

    assert_equal 0, Debug::Session.panels(frame: "2").first.locals[:frame_index]
  end

  test "there are no panels without a stop to inspect" do
    attach(FakeClient.new(snapshot: nil))

    assert_nil Debug::Session.panels(frame: "0")
  end

  test "there are no panels without a session" do
    assert_nil Debug::Session.panels(frame: "0")
  end

  # --- expanding locals ------------------------------------------------------

  test "expanding a local fetches its children from the client" do
    client = attach(FakeClient.new(state: :stopped))

    assert_equal [{name: "@a", value: "1"}], Debug::Session.expand("42")
    assert_equal 42, client.expanded
  end

  # A ref is a handle into the current stop; once running it points at nothing.
  test "a local cannot be expanded while the debuggee is running" do
    attach(FakeClient.new(state: :running))

    assert_nil Debug::Session.expand("42")
  end

  test "a scalar local has no children to expand" do
    attach(FakeClient.new(state: :stopped))

    assert_nil Debug::Session.expand("0")
  end

  test "nothing can be expanded without a session" do
    assert_nil Debug::Session.expand("42")
  end

  # --- evaluating ------------------------------------------------------------

  test "an expression is evaluated in the selected frame" do
    client = attach(FakeClient.new(snapshot: SNAPSHOT))

    Debug::Session.evaluate("user.name", frame: "1")

    assert_equal({expression: "user.name", frame_id: 22}, client.evaluated)
  end

  test "an out-of-range frame evaluates in the deepest frame" do
    client = attach(FakeClient.new(snapshot: SNAPSHOT))

    Debug::Session.evaluate("1 + 1", frame: "99")

    assert_equal 22, client.evaluated[:frame_id]
  end

  # The REPL prints this like a console would, rather than blowing up on a stale
  # frame id.
  test "evaluating away from a breakpoint returns a console-style error" do
    attach(FakeClient.new(state: :running, snapshot: SNAPSHOT))

    result = Debug::Session.evaluate("1 + 1", frame: "0")

    assert result[:error]
    assert_equal 0, result[:ref]
    assert_match(/not at a breakpoint/, result[:value])
  end

  test "evaluating without a session returns a console-style error" do
    assert Debug::Session.evaluate("1 + 1", frame: "0")[:error]
  end

  # --- encapsulation ---------------------------------------------------------

  test "wiring, connecting and clamping stay internal" do
    %i[wire_callbacks connect_with_retry frame_index].each do |internal|
      refute_respond_to Debug::Session, internal
    end
  end

  private

  def silence_broadcasts(&block)
    stub_method(Turbo::StreamsChannel, :broadcast_update_to, ->(*, **) {}, &block)
  end
end
