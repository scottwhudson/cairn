require "test_helper"

# Drives a real Debug::DapClient against an in-process FakeDapServer over an
# actual socket, so the framing, the reader/dispatcher threads, and snapshot
# construction are all exercised for real — no rdbg, no mocking of the wire.
class DapClientTest < ActiveSupport::TestCase
  def teardown
    @client&.disconnect
    @server&.close
  end

  # A connected client + its server. Does not prime past the initial pause, so
  # the handshake and pause-swallow behaviour can be tested in isolation.
  def connect!(repo_path: nil)
    @server = FakeDapServer.new.start
    @client = Debug::DapClient.new(host: "127.0.0.1", port: @server.port, repo_path: repo_path)
    @client.connect(timeout: 2)
    @client
  end

  # The first stop rdbg emits is the load/entry pause, which the client swallows
  # and auto-continues. Get past it so later stops are surfaced as snapshots.
  def prime_past_pause
    @server.stop(reason: "pause")
    @server.wait_until_request("continue")
  end

  # Capture stops as they're broadcast, so a test can block for the next one.
  def capture_stops
    stops = Queue.new
    @client.on_stop { |snapshot| stops << snapshot }
    stops
  end

  def next_stop(stops, timeout: 2)
    snapshot = stops.pop(timeout: timeout)
    assert snapshot, "no stop was broadcast within #{timeout}s"
    snapshot
  end

  # --- handshake -------------------------------------------------------------

  test "connect runs initialize then attach{localfs:true} and waits for initialized" do
    connect!

    commands = @server.requests.map { |r| r["command"] }
    assert_equal %w[initialize attach], commands.first(2)
    attach = @server.wait_until_request("attach")
    assert_equal true, attach["arguments"]["localfs"]
    assert_equal :connected, @client.state
  end

  test "connect captures the adapter capabilities" do
    connect!

    assert_equal true, @client.capabilities["supportsStepBack"]
  end

  test "connect times out if the adapter never sends initialized" do
    @server = FakeDapServer.new.start
    @server.on("attach") { {} } # respond, but never emit `initialized`
    @client = Debug::DapClient.new(host: "127.0.0.1", port: @server.port)

    assert_raises(Debug::DapClient::Timeout) { @client.connect(timeout: 0.5) }
  end

  # --- request / response ----------------------------------------------------

  test "a failed response raises Error carrying the adapter message" do
    connect!
    @server.fail_command("boom", "kaboom")

    error = assert_raises(Debug::DapClient::Error) { @client.send(:request, "boom") }
    assert_match(/kaboom/, error.message)
  end

  test "a request with no response times out" do
    connect!
    @server.on("hang") { :no_response }

    assert_raises(Debug::DapClient::Timeout) { @client.send(:request, "hang", {}, timeout: 0.3) }
  end

  # Two requests in flight, answered in reverse order: each caller must still get
  # its own response. Proves responses are routed by request_seq, not by arrival
  # order.
  test "concurrent requests are matched to their responses by seq" do
    connect!
    @server.defer("echo")

    results = {}
    a = Thread.new { results[:a] = @client.send(:request, "echo", {tag: "a"}) }
    b = Thread.new { results[:b] = @client.send(:request, "echo", {tag: "b"}) }
    @server.wait_until_request_count("echo", 2)
    @server.flush_deferred("echo", reverse: true)
    [a, b].each(&:join)

    assert_equal "a", results[:a].dig("body", "tag")
    assert_equal "b", results[:b].dig("body", "tag")
  end

  # --- execution control -----------------------------------------------------

  {continue: "continue", step_over: "next", step_in: "stepIn", step_out: "stepOut"}.each do |method, command|
    test "#{method} sends #{command.inspect} for the current thread and resumes" do
      connect!

      @client.public_send(method)

      request = @server.wait_until_request(command)
      assert_equal 1, request["arguments"]["threadId"]
      assert_equal true, request["arguments"]["singleThread"]
      assert_equal :running, @client.state
    end
  end

  # Control commands are fire-and-forget: the call returns without waiting for a
  # response (rdbg drives the outcome through the next `stopped` event instead).
  test "a control command returns without blocking on a response" do
    connect!
    @server.on("continue") { :no_response }

    assert_kind_of Integer, @client.continue
    assert_equal :running, @client.state
  end

  # A rejected control command has no waiter to raise into, so it surfaces
  # out-of-band via on_error.
  test "a rejected control command surfaces via on_error" do
    connect!
    errors = Queue.new
    @client.on_error { |command, message| errors << [command, message] }
    @server.fail_command("stepIn", "cannot step here")

    @client.step_in

    command, message = errors.pop(timeout: 2)
    assert_equal "stepIn", command
    assert_match(/cannot step here/, message)
  end

  # --- the initial pause -----------------------------------------------------

  test "the initial pause stop is swallowed and auto-continued, not surfaced" do
    connect!
    stops = capture_stops

    @server.stop(reason: "pause")

    @server.wait_until_request("continue") # the client auto-continued
    assert_nil stops.pop(timeout: 0.3), "the load/entry pause should not be broadcast"
    assert_equal :running, @client.state
  end

  # --- stopped -> snapshot ---------------------------------------------------

  test "a breakpoint stop builds a snapshot with source and locals" do
    connect!
    prime_past_pause
    stops = capture_stops

    @server.stop_with(frames: [
      {id: 1, name: "create", file: "/repo/app.rb", line: 42,
       locals: [{name: "order", value: "#<Order id: 7>", type: "Order"}]}
    ])

    snapshot = next_stop(stops)
    assert_equal "breakpoint", snapshot[:reason]
    assert_equal "/repo/app.rb", snapshot[:file]
    assert_equal 42, snapshot[:line]
    assert_equal 1, snapshot[:frames].size
    assert_includes snapshot[:locals].map { |l| l[:name] }, "order"
  end

  test "instance variables are flattened into the top frame's locals" do
    connect!
    prime_past_pause
    stops = capture_stops

    @server.stop_with(frames: [
      {id: 1, name: "create", file: "/repo/app.rb", line: 1,
       locals: [{name: "x", value: "1", type: "Integer"}],
       ivars: [{name: "@user", value: "#<User>", type: "User"}]}
    ])

    names = next_stop(stops)[:locals].map { |l| l[:name] }
    assert_includes names, "@user"      # flattened up from %self
    assert_includes names, "x"          # real local
    refute_includes names, "#class"     # the %self meta row is dropped
  end

  # ivars are only expanded for app frames and the top frame — expanding %self on a
  # framework frame would inspect huge objects on every step.
  test "framework-frame instance variables are not expanded" do
    connect!(repo_path: "/repo")
    prime_past_pause
    stops = capture_stops

    @server.stop_with(frames: [
      {id: 1, name: "create", file: "/repo/app.rb", line: 1, ivars: [{name: "@a", value: "1"}]},
      {id: 2, name: "call", file: "/gem/lib.rb", line: 9, ivars: [{name: "@b", value: "2"}]}
    ])

    snapshot = next_stop(stops)
    assert_includes snapshot[:frames][0][:locals].map { |l| l[:name] }, "@a"
    refute_includes snapshot[:frames][1][:locals].map { |l| l[:name] }, "@b"
  end

  # A value longer than a single socket read must be reassembled from the frame's
  # Content-Length, not truncated at a read boundary.
  test "a large variable value survives framing intact" do
    connect!
    prime_past_pause
    stops = capture_stops
    big = "x" * 5000

    @server.stop_with(frames: [
      {id: 1, name: "create", file: "/repo/app.rb", line: 1,
       locals: [{name: "blob", value: big, type: "String"}]}
    ])

    blob = next_stop(stops)[:locals].find { |l| l[:name] == "blob" }
    assert_equal big, blob[:value]
  end

  test "an exception stop carries the unwrapped exception text" do
    connect!
    prime_past_pause
    stops = capture_stops

    @server.stop_with(
      reason: "exception",
      text: "#<ArgumentError: boom> is raised.",
      frames: [{id: 1, name: "create", file: "/repo/app.rb", line: 1}]
    )

    assert_equal "ArgumentError: boom", next_stop(stops)[:exception]
  end

  # A deep frame that can't resolve its scope must degrade to empty locals rather
  # than abort the whole snapshot.
  test "a frame whose scopes request fails degrades to empty locals" do
    connect!
    prime_past_pause
    stops = capture_stops
    @server.on("stackTrace") do
      {stackFrames: [{id: 1, name: "create", source: {path: "/repo/app.rb"}, line: 1}]}
    end
    @server.fail_command("scopes", "no scope here")
    @server.stop(reason: "breakpoint")

    snapshot = next_stop(stops)
    assert_equal 1, snapshot[:frames].size
    assert_empty snapshot[:locals]
  end

  # The exact failure the dispatcher's in-loop rescue guards against: if a bad stop
  # killed the dispatcher, every later step would silently stop updating the UI.
  test "the dispatcher survives a stop whose stackTrace fails" do
    connect!
    prime_past_pause
    stops = capture_stops

    @server.fail_command("stackTrace", "boom")
    @server.stop(reason: "breakpoint")
    @server.wait_until_request("stackTrace")        # the bad stop was processed...
    assert_nil stops.pop(timeout: 0.3), "the failed stop should not broadcast a snapshot"

    @server.stop_with(frames: [{id: 1, name: "create", file: "/repo/app.rb", line: 1}])
    assert next_stop(stops), "a later good stop must still be handled"
  end

  # --- expanding a structured value -----------------------------------------

  test "expand returns a value's children" do
    connect!
    @server.on("variables") do
      {variables: [{name: "@id", value: "7", type: "Integer", variablesReference: 0}]}
    end

    children = @client.expand(555)
    assert_equal "@id", children.first[:name]
  end

  # rdbg pads structured values with meta rows; the client drops the redundant
  # #class and turns #dump (the untruncated string) into a readable full-value row.
  test "expand drops the #class row and turns #dump into a full-value row" do
    connect!
    @server.on("variables") do
      {variables: [
        {name: "@id", value: "7", type: "Integer", variablesReference: 0},
        {name: "#class", value: "Widget", type: "Class"},
        {name: "#dump", value: "the whole long string".dump, type: "String"}
      ]}
    end

    children = @client.expand(555)
    names = children.map { |c| c[:name] }
    refute_includes names, "#class"
    full = children.find { |c| c[:name] == "(full value)" }
    assert_equal "the whole long string", full[:value]
  end

  test "expand degrades to [] on an adapter error" do
    connect!
    @server.fail_command("variables", "stale ref")

    assert_equal [], @client.expand(999)
  end

  # --- evaluating an expression ---------------------------------------------

  test "evaluate returns the result value, type and ref" do
    connect!
    @server.on("evaluate") { {result: "42", type: "Integer", variablesReference: 0} }

    result = @client.evaluate("6 * 7", frame_id: 1)
    assert_equal "42", result[:value]
    assert_equal "Integer", result[:type]
    assert_equal 0, result[:ref]
  end

  # A bad expression is printed like a console would, not raised.
  test "evaluate returns a console-style error instead of raising" do
    connect!
    @server.fail_command("evaluate", "NameError: undefined local variable foo")

    result = @client.evaluate("foo")
    assert result[:error]
    assert_equal "NameError: undefined local variable foo", result[:value]
    assert_equal 0, result[:ref]
  end

  # --- exception breakpoints -------------------------------------------------

  test "arming break_on_exception sends the any filter" do
    connect!

    @client.break_on_exception = true

    request = @server.wait_until_request("setExceptionBreakpoints")
    assert_equal ["any"], request["arguments"]["filters"]
    assert @client.break_on_exception
  end

  test "disarming break_on_exception clears the filters" do
    connect!
    @client.break_on_exception = true

    @client.break_on_exception = false

    # the last setExceptionBreakpoints carried an empty filter list
    last = @server.requests.rfind { |r| r["command"] == "setExceptionBreakpoints" }
    assert_equal [], last["arguments"]["filters"]
    refute @client.break_on_exception
  end

  # --- lifecycle -------------------------------------------------------------

  test "detach disconnects without terminating the debuggee, then closes" do
    connect!

    @client.detach

    request = @server.wait_until_request("disconnect")
    assert_equal false, request["arguments"]["terminateDebuggee"]
    assert_equal :terminated, @client.state
  end

  test "a terminated event moves the client to :terminated" do
    connect!
    states = Queue.new
    @client.on_state { |state| states << state }

    @server.event("terminated")

    wait_for_state(states, :terminated)
    assert_equal :terminated, @client.state
  end

  test "state transitions fire the on_state callback" do
    connect!
    states = Queue.new
    @client.on_state { |state| states << state }

    @client.continue # :connected -> :running

    wait_for_state(states, :running)
  end

  private

  def wait_for_state(states, target, timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      flunk "never reached #{target.inspect}" if remaining <= 0
      return if states.pop(timeout: remaining) == target
    end
  end
end
