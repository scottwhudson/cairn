# Shared scaffolding for the debug-session controllers. Each of them is a thin
# HTTP shell over Debug::Session: it translates params into calls, and the
# session's answers into responses. These helpers stand in for the session (whose
# real methods talk to a socket) so no rdbg server is needed, and let the tests
# assert on that translation.
#
# Direction B split the session from its client: Debug::Session.current hands back
# a Session that wraps the DapClient. So the helpers below wrap a FakeClient in a
# real Session and stub whichever surface a test drives — the stop-scoped methods
# (step/panels/expand/evaluate/break_on_exception) on the session instance, and
# the lifecycle methods (attach/detach) on the class.
module DebugSessionTestHelper
  SOURCE = Rails.root.join("app/services/debug/session.rb").to_s

  SNAPSHOT = {
    reason: "breakpoint",
    file: SOURCE,
    line: 10,
    frames: [{id: 11, name: "attach", file: SOURCE, line: 10, locals: []}],
    locals: []
  }.freeze

  class FakeClient
    attr_reader :host, :port, :snapshot, :state, :break_on_exception

    def initialize(snapshot: nil, state: :stopped, break_on_exception: false)
      @host = "127.0.0.1"
      @port = 12345
      @snapshot = snapshot
      @state = state
      @break_on_exception = break_on_exception
    end

    def repo_path = Rails.root.to_s
  end

  # The lifecycle calls stay on the class; everything else is a stop-scoped method
  # on the session instance `current` returns.
  LIFECYCLE = %i[attach detach].freeze

  # Stub a session method for the duration of the block. Lifecycle calls are
  # stubbed on the class; stop-scoped calls on the live session that `current`
  # hands back (standing one up if the test didn't pin its own client).
  def stub_session(method, impl, &block)
    return stub_method(Debug::Session, method, impl, &block) if LIFECYCLE.include?(method)

    return stub_method(@session_double, method, impl, &block) if @session_double

    with_attached_session(FakeClient.new) { stub_method(@session_double, method, impl, &block) }
  end

  # Pin what `Debug::Session.current` returns for the block: a real Session wrapping
  # the given client, or a NullSession when detached (current: nil).
  def with_session(current:, &block)
    session = current.nil? ? Debug::Session::NullSession.new : Debug::Session.new(current)
    @session_double = session
    stub_method(Debug::Session, :current, -> { @session_double }, &block)
  end

  def with_attached_session(client, &block) = with_session(current: client, &block)

  def turbo_streams = css_select("turbo-stream")

  def sole_turbo_stream
    assert_equal 1, turbo_streams.size
    turbo_streams.first
  end
end
