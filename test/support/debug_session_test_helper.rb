# Shared scaffolding for the debug-session controllers. Each of them is a thin
# HTTP shell over Debug::Session: it translates params into calls, and the
# session's answers into responses. These helpers stand in for the session (whose
# real methods talk to a socket) so no rdbg server is needed, and let the tests
# assert on that translation.
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

  def stub_session(method, impl, &block) = stub_method(Debug::Session, method, impl, &block)

  def with_session(current:, &block) = stub_session(:current, -> { current }, &block)

  # StatusComponent decides it's attached from the client it's handed, so stubbing
  # the session is enough — nothing reads the registry behind our back.
  def with_attached_session(client, &block) = with_session(current: client, &block)

  def turbo_streams = css_select("turbo-stream")

  def sole_turbo_stream
    assert_equal 1, turbo_streams.size
    turbo_streams.first
  end
end
