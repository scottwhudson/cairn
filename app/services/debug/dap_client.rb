require "socket"
require "json"
require "monitor"

module Debug
  # A minimal Debug Adapter Protocol (DAP) client that speaks to an `rdbg --open`
  # server over a TCP socket. No extra gem — just Content-Length framed JSON.
  #
  # Threading model (deliberate, to avoid deadlocks):
  #   * a *reader* thread does nothing but read frames off the socket. Responses
  #     are handed back to whichever thread is blocked in #request; events are
  #     pushed onto an internal queue.
  #   * a *dispatcher* thread drains that queue. Only the dispatcher reacts to
  #     `stopped` events — and reacting means issuing further requests (stackTrace,
  #     scopes, variables). Doing that from the reader thread would deadlock,
  #     since the reader would be waiting on itself to deliver the response.
  #
  # Handshake (verified against rdbg 1.11.1):
  #   initialize -> attach{localfs:true} -> (initialized event) -> setBreakpoints
  #   -> configurationDone -> stopped(pause) -> continue -> stopped(breakpoint)
  class DapClient
    class Error < StandardError; end
    class Timeout < Error; end

    attr_reader :host, :port, :snapshot, :capabilities, :state
    attr_accessor :repo_path  # source root for relative-path display in the UI

    def initialize(host:, port:, logger: nil, repo_path: nil)
      @host = host
      @port = port
      @logger = logger
      @repo_path = repo_path

      @seq = 0
      @seq_lock = Mutex.new
      @pending = {}          # request seq => Queue awaiting the response
      @pending_lock = Monitor.new
      @event_queue = Queue.new
      @initialized_latch = Queue.new  # created up front so the event is never missed

      @snapshot = nil        # the current stop (source/frames/locals), or nil while running
      @capabilities = {}
      @state = :new          # :new -> :connected -> :running -> :stopped -> :terminated
      @started = false
      @thread_id = 1
    end

    def on_stop(&blk) = (@on_stop = blk)
    def on_state(&blk) = (@on_state = blk)
    def on_error(&blk) = (@on_error = blk)

    # Open the socket, start the pump threads, and run the initialize/attach
    # portion of the handshake. Returns once the adapter is ready for breakpoints.
    def connect(timeout: 10)
      @socket = TCPSocket.new(@host, @port)
      @reader = Thread.new { read_loop }
      @dispatcher = Thread.new { dispatch_loop }

      resp = request("initialize", {
        clientID: "cairn", adapterID: "rdbg",
        linesStartAt1: true, columnsStartAt1: true, pathFormat: "path",
        supportsRunInTerminalRequest: false
      }, timeout: timeout)
      @capabilities = resp["body"] || {}

      # localfs:true tells rdbg the client shares its filesystem, so absolute
      # source paths map directly and breakpoints can be verified.
      request("attach", {localfs: true}, timeout: timeout)
      wait_for_initialized(timeout)
      transition(:connected)
      self
    end

    # breakpoints: [{ line:, condition:, waypoint_id: }, ...]
    # Returns the verified breakpoint descriptors from the adapter.
    def set_breakpoints(abs_path, breakpoints)
      resp = request("setBreakpoints", {
        source: {path: abs_path},
        breakpoints: breakpoints.map { |b| {line: b[:line], condition: b[:condition]}.compact }
      })
      resp.dig("body", "breakpoints") || []
    end

    def configuration_done
      request("configurationDone")
    end

    # Fetch the children of a structured variable (hash/array/object) by its
    # `variablesReference`, so the UI can drill into a local on demand. Only valid
    # while stopped — refs are handles into the current stop and go stale on the
    # next resume. Degrades to [] on any adapter error so a stale/bad ref never
    # surfaces as a 500.
    def expand(ref)
      return [] if ref.nil? || ref.to_i.zero?
      clean_children(variables_for(ref).map { |v| var_entry(v) })
    rescue Error => e
      log("expand #{ref} failed: #{e.message}")
      []
    end

    # Evaluate an expression in the context of a frame (the selected call-stack
    # frame), like typing into a debugger console. Unlike execution-control
    # commands, `evaluate` returns a real response, so we can block on it. A
    # structured result carries a `ref` the UI can drill into via #expand. Errors
    # (bad syntax, NameError, …) come back as a value flagged :error rather than
    # raising, so the REPL can print them like a console would.
    def evaluate(expression, frame_id: nil)
      args = {expression: expression, context: "repl"}
      args[:frameId] = frame_id if frame_id
      body = request("evaluate", args)["body"] || {}
      {value: body["result"], type: body["type"], ref: body["variablesReference"].to_i}
    rescue Error => e
      {value: e.message.sub(/\A'evaluate' failed: /, ""), type: nil, ref: 0, error: true}
    end

    # --- execution control ---------------------------------------------------

    def continue = control("continue")
    def step_over = control("next")
    def step_in = control("stepIn")
    def step_out = control("stepOut")

    # Detach from the running server without killing it. We attached to a process
    # the user is running (their Rails server), so we send DAP `disconnect` with
    # terminateDebuggee:false and let it keep serving requests.
    def detach
      request("disconnect", {terminateDebuggee: false}, timeout: 3)
    rescue Error
      # adapter may already be gone
    ensure
      disconnect
    end

    def disconnect
      @socket&.close
    rescue IOError
      # already closed
    ensure
      transition(:terminated) unless @state == :terminated
    end

    private

    # Execution-control commands are fire-and-forget: rdbg drives the result
    # through a subsequent `stopped` event rather than a reliable response
    # (reverse steps in particular emit only the event). We don't block the
    # caller; a failure response with no waiter is surfaced via #on_error.
    def control(command)
      seq = next_seq
      write_message({seq: seq, type: "request", command: command,
                      arguments: {threadId: @thread_id, singleThread: true}})
      # Execution has resumed and left the current stop. Signal :running so the
      # UI can reset the stop-specific panels; the next `stopped` repopulates them
      # (or the debuggee just keeps running if nothing else stops it).
      transition(:running)
      seq
    end

    # ---- request/response ----------------------------------------------------

    def request(command, arguments = {}, timeout: 15)
      seq = next_seq
      queue = Queue.new
      @pending_lock.synchronize { @pending[seq] = queue }
      write_message({seq: seq, type: "request", command: command, arguments: arguments})

      resp = queue.pop(timeout: timeout)
      raise Timeout, "no response to '#{command}' within #{timeout}s" if resp.nil?
      unless resp["success"]
        raise Error, "'#{command}' failed: #{resp["message"] || "unknown error"}"
      end
      resp
    ensure
      @pending_lock.synchronize { @pending.delete(seq) }
    end

    # ---- socket pumps --------------------------------------------------------

    def read_loop
      loop do
        msg = read_message
        break if msg.nil?
        case msg["type"]
        when "response"
          deliver_response(msg)
        when "event"
          @event_queue << msg
        end
      end
    rescue IOError, Errno::EBADF, Errno::ECONNRESET
      # socket closed; fall through
    ensure
      @event_queue << :__eof__
    end

    def deliver_response(msg)
      seq = msg["request_seq"]
      queue = @pending_lock.synchronize { @pending[seq] }
      if queue
        queue.push(msg)
      elsif msg["success"] == false
        # A fire-and-forget control command that the adapter rejected.
        @on_error&.call(msg["command"], msg["message"])
      end
    end

    def dispatch_loop
      loop do
        ev = @event_queue.pop
        break if ev == :__eof__
        begin
          handle_event(ev)
        rescue => e
          # A single bad event must never kill the dispatcher — if it did, every
          # later `stopped` event (i.e. every step) would go unhandled and the UI
          # would silently stop updating. Log and keep draining the queue.
          log("dispatch error handling #{ev["event"] if ev.is_a?(Hash)}: #{e.class}: #{e.message}")
        end
      end
    end

    def handle_event(ev)
      case ev["event"]
      when "initialized"
        @initialized_latch&.push(true)
      when "stopped"
        handle_stopped(ev)
      when "terminated", "exited"
        transition(:terminated)
      when "output"
        log("[debuggee] #{ev.dig("body", "output")&.strip}")
      end
    end

    def handle_stopped(ev)
      reason = ev.dig("body", "reason")
      @thread_id = ev.dig("body", "threadId") || @thread_id

      # The initial load/entry stop: run through to the first real breakpoint.
      # Not surfaced to the reviewer.
      if !@started && %w[pause entry step].include?(reason)
        @started = true
        transition(:running)
        continue
        return
      end

      transition(:stopped)
      @snapshot = build_snapshot(reason)
      @on_stop&.call(@snapshot)
    end

    # ---- snapshot construction ----------------------------------------------

    def build_snapshot(reason)
      frames = stack_frames
      # Capture locals for every frame now, while the frame ids are still valid
      # (they go stale on the next resume). This lets selecting a frame re-render
      # from the current snapshot without another round-trip. Per-frame rescue: a
      # deep frame that can't resolve its scope must degrade to empty locals,
      # never abort the whole snapshot.
      #
      # Instance vars are only expanded for app frames (source under repo_path):
      # that's the code under review, and it avoids inspecting the huge `self` of
      # framework frames (the Rails app, middleware) on every step. When repo_path
      # isn't set we only expand the top frame — enough for the current stop
      # without walking the whole stack.
      frames.each do |f|
        f[:locals] = safe_locals_for(f[:id], ivars: expand_ivars?(f, top: f.equal?(frames.first)))
      end
      top = frames.first || {}
      {
        reason: reason,
        file: top[:file],
        line: top[:line],
        frames: frames,
        locals: top[:locals] || [],
        at: Time.now.to_f
      }
    end

    # Fetch a deep window of the stack so callers below the top frame are
    # available to inspect and scroll through. Bounded because build_snapshot
    # eagerly fetches locals per frame — a full Rails stack would be hundreds.
    MAX_FRAMES = 50

    def stack_frames
      resp = request("stackTrace", {threadId: @thread_id, startFrame: 0, levels: MAX_FRAMES})
      (resp.dig("body", "stackFrames") || []).filter_map do |f|
        path = f.dig("source", "path")
        next if path.nil? # skip frames without source (C / internal)
        {id: f["id"], name: f["name"], file: path, line: f["line"]}
      end
    end

    # Expand `%self`'s ivars for app frames (under repo_path); otherwise only for
    # the top (currently-stopped) frame. Keeps stepping snappy on deep stacks.
    def expand_ivars?(frame, top:)
      return true if top
      repo_path.present? && frame[:file].to_s.start_with?("#{repo_path}/")
    end

    def safe_locals_for(frame_id, ivars: true)
      locals_for(frame_id, ivars: ivars)
    rescue Error => e
      log("locals unavailable for frame #{frame_id}: #{e.message}")
      []
    end

    def locals_for(frame_id, ivars: true)
      return [] if frame_id.nil?
      scopes = request("scopes", {frameId: frame_id}).dig("body", "scopes") || []
      local_scope = scopes.find { |s| s["name"] =~ /local/i } || scopes.first
      return [] unless local_scope
      ref = local_scope["variablesReference"]
      return [] if ref.nil? || ref.zero?
      vars = variables_for(ref)
      entries = vars.map { |v| var_entry(v) }
      ivars ? entries + instance_vars_from(vars) : entries
    end

    # rdbg exposes the receiver as a `%self` pseudo-local whose children are the
    # instance variables. Flatten them up so ivars set before the breakpoint
    # (e.g. a controller's @-vars) show in the locals pane instead of staying
    # hidden one level down inside self.
    def instance_vars_from(scope_vars)
      selff = scope_vars.find { |v| v["name"] == "%self" }
      ref = selff && selff["variablesReference"]
      return [] if ref.nil? || ref.to_i.zero?
      variables_for(ref).filter_map do |v|
        var_entry(v) if v["name"].to_s.start_with?("@")
      end
    rescue Error => e
      log("instance vars unavailable: #{e.message}")
      []
    end

    def variables_for(ref)
      request("variables", {variablesReference: ref}).dig("body", "variables") || []
    end

    # rdbg pads a structured value's children with meta rows: a `#class` entry
    # (redundant with the `type` column every row already shows) and, for strings
    # it had to truncate, a `#dump` entry whose value is the *complete* content.
    # rdbg caps every inspected value at 180 chars, so for a long string `#dump`
    # is the only way to see the rest — but it arrives as an escaped Ruby literal
    # labelled `#dump`, which reads as metadata rather than "the string". Drop the
    # redundant class row and turn `#dump` into a readable "(full value)" row so
    # expanding a string surfaces its actual contents.
    def clean_children(entries)
      entries.filter_map do |e|
        case e[:name]
        when "#class"
          nil
        when "#dump"
          e.merge(name: "(full value)", value: undump(e[:value]), type: "String")
        else
          e
        end
      end
    end

    # Reverse String#dump (rdbg sends the full string as a dumped literal). Falls
    # back to the raw dumped form if it isn't a well-formed dump.
    def undump(dumped)
      dumped.to_s.undump
    rescue
      dumped
    end

    def var_entry(v)
      {name: v["name"], value: v["value"], type: v["type"], ref: v["variablesReference"]}
    end

    # ---- framing -------------------------------------------------------------

    def write_message(msg)
      body = JSON.generate(msg)
      @write_lock ||= Mutex.new
      @write_lock.synchronize do
        @socket.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
      end
    end

    def read_message
      header = +""
      until header.end_with?("\r\n\r\n")
        ch = @socket.read(1)
        return nil if ch.nil?
        header << ch
      end
      length = header[/Content-Length: (\d+)/i, 1].to_i
      body = @socket.read(length)
      return nil if body.nil?
      JSON.parse(body)
    end

    # ---- misc ----------------------------------------------------------------

    def wait_for_initialized(timeout)
      got = @initialized_latch.pop(timeout: timeout)
      raise Timeout, "adapter never sent the 'initialized' event" if got.nil?
    end

    def next_seq
      @seq_lock.synchronize { @seq += 1 }
    end

    def transition(new_state)
      return if @state == new_state
      @state = new_state
      @on_state&.call(new_state)
    end

    def log(msg)
      @logger&.info("[DapClient] #{msg}")
    end
  end
end
