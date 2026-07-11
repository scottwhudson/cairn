require "socket"
require "json"
require "monitor"

# An in-process stand-in for rdbg's DAP server, speaking the same Content-Length
# framed JSON over a *real* TCP socket. It lets DapClient tests exercise the
# actual socket I/O, message framing, and reader/dispatcher threads without a
# live rdbg — the client can't tell it apart from the real adapter.
#
# It accepts one connection, auto-answers the handshake/lifecycle requests, and
# lets a test script further responses (#on, #fail_command, #defer) and push
# events (#event, #stop, #stop_with). Every request the client sends is recorded;
# #wait_until_request blocks until an expected one lands, so tests synchronize on
# protocol traffic — never on sleeps — despite the client's background threads.
class FakeDapServer
  # A handler returning this responds with success:false and the given message.
  Reject = Struct.new(:message)

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @handlers = {}
    @deferred = Hash.new { |h, k| h[k] = [] } # command => [requests awaiting flush]
    @requests = []
    @monitor = Monitor.new                     # guards @requests + signals waiters
    @cond = @monitor.new_cond
    @write_lock = Mutex.new                    # responses (server thread) vs events (test thread)
    @seq = 0
    @var_sets = {}                             # variablesReference => [variable, ...]
    install_defaults
  end

  def port = @server.addr[1]

  def start
    @thread = Thread.new { serve }
    self
  end

  # Register a handler. The block gets (arguments, full_request) and returns the
  # response body Hash, a Reject (→ success:false), or :no_response to stay silent
  # (so the client's request times out).
  def on(command, &block) = @handlers[command] = block

  def fail_command(command, message) = on(command) { Reject.new(message) }

  # Buffer a command's requests instead of answering, so a test can release the
  # responses out of order via #flush_deferred and prove seq-based matching.
  def defer(command) = on(command) { |_args, req|
    @deferred[command] << req
    :no_response
  }

  def flush_deferred(command, reverse: false)
    reqs = @deferred[command]
    reqs = reqs.reverse if reverse
    reqs.each { |req| respond(req, req["arguments"] || {}) }
    reqs.clear
  end

  # --- events pushed at the client ------------------------------------------

  def event(name, body = {}) = write({seq: next_seq, type: "event", event: name, body: body})

  def stop(reason:, text: nil, thread_id: 1)
    body = {reason: reason, threadId: thread_id}
    body[:text] = text if text
    event("stopped", body)
  end

  # Program the stackTrace/scopes/variables responses for one stop, then emit it.
  # `frames` is [{id:, name:, file:, line:, locals: [...], ivars: [...]}], outermost
  # (the stopped frame) first — the order rdbg returns.
  def stop_with(frames:, reason: "breakpoint", text: nil)
    program_frames(frames)
    stop(reason: reason, text: text)
  end

  # --- introspection / synchronization --------------------------------------

  def requests = @monitor.synchronize { @requests.dup }

  # Block until a request for `command` has been received; return it. Raises on
  # timeout so a wedged test fails loudly instead of hanging.
  def wait_until_request(command, timeout: 2)
    wait_until(timeout, "a #{command.inspect} request") do
      @requests.find { |r| r["command"] == command }
    end
  end

  def wait_until_request_count(command, count, timeout: 2)
    wait_until(timeout, "#{count} #{command.inspect} requests") do
      @requests.count { |r| r["command"] == command } >= count || nil
    end
  end

  def close
    @conn&.close
  rescue IOError
    # already closed
  ensure
    begin
      @server.close
    rescue IOError
      # already closed
    end
    @thread&.kill
  end

  private

  def serve
    @conn = @server.accept
    loop do
      msg = read_message
      break if msg.nil?
      record(msg)
      dispatch(msg)
    end
  rescue IOError, Errno::EBADF, Errno::ECONNRESET
    # client closed the socket
  end

  def record(msg)
    @monitor.synchronize do
      @requests << msg
      @cond.broadcast
    end
  end

  def dispatch(msg)
    handler = @handlers[msg["command"]] || ->(_a, _r) { {} }
    result = handler.call(msg["arguments"] || {}, msg)
    case result
    when :no_response then nil
    when Reject then respond(msg, {}, success: false, message: result.message)
    else respond(msg, result)
    end
  rescue => e
    # A broken handler must not wedge the read loop; surface it as a failed response.
    respond(msg, {}, success: false, message: "fake server handler error: #{e.message}")
  end

  def respond(request, body, success: true, message: nil)
    frame = {seq: next_seq, type: "response", request_seq: request["seq"],
             success: success, command: request["command"], body: body}
    frame[:message] = message if message
    write(frame)
  end

  def install_defaults
    on("initialize") do
      {supportsStepBack: true,
       exceptionBreakpointFilters: [{filter: "any", label: "any exception"}]}
    end
    # attach triggers the `initialized` event the client waits on before
    # configurationDone — the same order rdbg drives.
    on("attach") { |_a, _r|
      event("initialized")
      {}
    }
    on("configurationDone") { {} }
    on("setExceptionBreakpoints") { {} }
    on("disconnect") { {} }
  end

  # Build stackTrace + per-frame scopes/variables from a simple frame spec, so a
  # single #stop_with produces a full snapshot round-trip.
  def program_frames(frames)
    @var_sets = {}
    stack = frames.map do |f|
      scope_ref = ref_for(:scope, f[:id])
      self_ref = ref_for(:self, f[:id])
      # The local scope lists %self first (whose children are the ivars), then the
      # real locals — the shape DapClient#locals_for and #instance_vars_from expect.
      @var_sets[scope_ref] = [self_var(self_ref)] + Array(f[:locals])
      # %self's children: the @ivars, plus a #class sibling the client must ignore.
      @var_sets[self_ref] = Array(f[:ivars]) + [{name: "#class", value: f[:name], type: "Class"}]
      {id: f[:id], name: f[:name], source: {path: f[:file]}, line: f[:line], column: 1}
    end

    on("stackTrace") { {stackFrames: stack} }
    on("scopes") do |args|
      {scopes: [{name: "Local", variablesReference: ref_for(:scope, args["frameId"]), expensive: false}]}
    end
    on("variables") { |args| {variables: @var_sets[args["variablesReference"]] || []} }
  end

  def self_var(ref) = {name: "%self", value: "#<Object>", type: "Object", variablesReference: ref}

  def ref_for(kind, frame_id) = ((kind == :scope) ? 100_000 : 200_000) + frame_id.to_i

  # --- generic wait ----------------------------------------------------------

  def wait_until(timeout, description)
    deadline = monotonic + timeout
    @monitor.synchronize do
      loop do
        result = yield
        return result if result
        remaining = deadline - monotonic
        raise "timed out waiting for #{description}" if remaining <= 0
        @cond.wait(remaining)
      end
    end
  end

  # --- framing (mirrors DapClient) -------------------------------------------

  def write(msg)
    body = JSON.generate(msg)
    @write_lock.synchronize { @conn.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}") }
  rescue IOError, Errno::EPIPE
    # client gone
  end

  def read_message
    header = +""
    until header.end_with?("\r\n\r\n")
      ch = @conn.read(1)
      return nil if ch.nil?
      header << ch
    end
    length = header[/Content-Length: (\d+)/i, 1].to_i
    body = @conn.read(length)
    body && JSON.parse(body)
  end

  def next_seq = (@seq += 1)

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
