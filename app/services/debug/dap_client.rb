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
  #   -> configurationDone -> stopped(pause) -> `,record on` + continue -> stopped(breakpoint)
  class DapClient
    class Error < StandardError; end
    class Timeout < Error; end

    attr_reader :history, :capabilities, :state
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

      @history = []          # ordered list of user-facing stop snapshots
      @history_lock = Mutex.new
      @capabilities = {}
      @state = :new          # :new -> :connected -> :running -> :stopped -> :terminated
      @started = false
      @thread_id = 1
    end

    def on_stop(&blk)  = (@on_stop = blk)
    def on_state(&blk) = (@on_state = blk)
    def on_error(&blk) = (@on_error = blk)

    # Open the socket, start the pump threads, and run the initialize/attach
    # portion of the handshake. Returns once the adapter is ready for breakpoints.
    def connect(timeout: 10)
      @socket = TCPSocket.new(@host, @port)
      @reader = Thread.new { read_loop }
      @dispatcher = Thread.new { dispatch_loop }

      resp = request("initialize", {
        clientID: "tour-of-changes", adapterID: "rdbg",
        linesStartAt1: true, columnsStartAt1: true, pathFormat: "path",
        supportsRunInTerminalRequest: false
      }, timeout: timeout)
      @capabilities = resp["body"] || {}

      # localfs:true tells rdbg the client shares its filesystem, so absolute
      # source paths map directly and breakpoints can be verified.
      request("attach", { localfs: true }, timeout: timeout)
      wait_for_initialized(timeout)
      transition(:connected)
      self
    end

    # breakpoints: [{ line:, condition:, waypoint_id: }, ...]
    # Returns the verified breakpoint descriptors from the adapter.
    def set_breakpoints(abs_path, breakpoints)
      resp = request("setBreakpoints", {
        source: { path: abs_path },
        breakpoints: breakpoints.map { |b| { line: b[:line], condition: b[:condition] }.compact }
      })
      resp.dig("body", "breakpoints") || []
    end

    def configuration_done
      request("configurationDone")
    end

    # --- execution control ---------------------------------------------------

    def continue = control("continue")
    def step_over = control("next")
    def step_in  = control("stepIn")
    def step_out = control("stepOut")
    def step_back = control("stepBack")

    # Detach from the running server without killing it. We attached to a process
    # the user is running (their Rails server), so we send DAP `disconnect` with
    # terminateDebuggee:false and let it keep serving requests.
    def detach
      request("disconnect", { terminateDebuggee: false }, timeout: 3)
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

    def snapshot(index)
      @history_lock.synchronize { @history[index] }
    end

    def latest_index
      @history_lock.synchronize { @history.size - 1 }
    end

    private

    # Execution-control commands are fire-and-forget: rdbg drives the result
    # through a subsequent `stopped` event rather than a reliable response
    # (reverse steps in particular emit only the event). We don't block the
    # caller; a failure response with no waiter is surfaced via #on_error.
    def control(command)
      seq = next_seq
      write_message({ seq: seq, type: "request", command: command,
                      arguments: { threadId: @thread_id, singleThread: true } })
      seq
    end

    # ---- request/response ----------------------------------------------------

    def request(command, arguments = {}, timeout: 15)
      seq = next_seq
      queue = Queue.new
      @pending_lock.synchronize { @pending[seq] = queue }
      write_message({ seq: seq, type: "request", command: command, arguments: arguments })

      resp = queue.pop(timeout: timeout)
      raise Timeout, "no response to '#{command}' within #{timeout}s" if resp.nil?
      unless resp["success"]
        raise Error, "'#{command}' failed: #{resp['message'] || 'unknown error'}"
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
        # A fire-and-forget control command that the adapter rejected
        # (e.g. stepBack with no recorded history to rewind into).
        @on_error&.call(msg["command"], msg["message"])
      end
    end

    def dispatch_loop
      loop do
        ev = @event_queue.pop
        break if ev == :__eof__
        handle_event(ev)
      end
    rescue => e
      log("dispatch error: #{e.class}: #{e.message}")
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
        log("[debuggee] #{ev.dig('body', 'output')&.strip}")
      end
    end

    def handle_stopped(ev)
      reason = ev.dig("body", "reason")
      @thread_id = ev.dig("body", "threadId") || @thread_id

      # The initial load/entry stop: turn on record/replay so `stepBack` works,
      # then run to the first real breakpoint. Not surfaced to the reviewer.
      if !@started && %w[pause entry step].include?(reason)
        @started = true
        enable_recording
        transition(:running)
        continue
        return
      end

      transition(:stopped)
      snap = build_snapshot(reason)
      @history_lock.synchronize { snap[:index] = @history.size; @history << snap }
      @on_stop&.call(snap)
    end

    def enable_recording
      request("evaluate", { expression: ",record on", context: "repl" })
    rescue Error => e
      log("could not enable recording: #{e.message}")
    end

    # ---- snapshot construction ----------------------------------------------

    def build_snapshot(reason)
      frames = stack_frames
      top = frames.first || {}
      {
        reason: reason,
        file: top[:file],
        line: top[:line],
        frames: frames,
        locals: locals_for(top[:id]),
        at: Time.now.to_f
      }
    end

    def stack_frames
      resp = request("stackTrace", { threadId: @thread_id, startFrame: 0, levels: 20 })
      (resp.dig("body", "stackFrames") || []).filter_map do |f|
        path = f.dig("source", "path")
        next if path.nil? # skip frames without source (C / internal)
        { id: f["id"], name: f["name"], file: path, line: f["line"] }
      end
    end

    def locals_for(frame_id)
      return [] if frame_id.nil?
      scopes = request("scopes", { frameId: frame_id }).dig("body", "scopes") || []
      local_scope = scopes.find { |s| s["name"] =~ /local/i } || scopes.first
      return [] unless local_scope
      ref = local_scope["variablesReference"]
      return [] if ref.nil? || ref.zero?
      vars = request("variables", { variablesReference: ref }).dig("body", "variables") || []
      vars.map do |v|
        { name: v["name"], value: v["value"], type: v["type"], ref: v["variablesReference"] }
      end
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
