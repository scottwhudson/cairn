module Debug
  # The debug session as the app talks about it: attach, drive execution, inspect
  # the current stop, detach. Wraps the one live DapClient parked in
  # SessionRegistry and keeps its callbacks wired to a SessionBroadcaster, so the
  # controller never has to know how a stop reaches the browser.
  module Session
    class AlreadyAttached < StandardError; end

    STEP_COMMANDS = {
      "continue" => :continue,
      "next" => :step_over,
      "step_in" => :step_in,
      "step_out" => :step_out
    }.freeze

    module_function

    def current = SessionRegistry.get

    def attached? = SessionRegistry.active?

    # Attach to a running rdbg DAP server (e.g. a Rails server started with
    # `rdbg --open`). Returns the connected client, whose reader/dispatcher
    # threads outlive the request that created it.
    # `repo_path` is the debuggee's source root. Cairn runs in its own process, and
    # DAP never reports where the target's code lives, so it has to be told: it's
    # what separates app frames from gem frames, and what shortens absolute paths
    # for display. A trailing slash would break both (they compare against
    # "#{repo_path}/"), so normalize it away.
    def attach(host:, port:, repo_path: nil, logger: Rails.logger)
      raise AlreadyAttached if attached?

      client = DapClient.new(
        host: host.presence || "127.0.0.1", port: port.to_i, logger: logger,
        repo_path: repo_path.presence&.strip&.chomp("/")
      )
      wire_callbacks(client)
      connect_with_retry(client)
      client.configuration_done
      SessionRegistry.put(client)
      client
    end

    def detach
      current&.detach
      SessionRegistry.clear
    end

    # Drive execution. Fire-and-forget: the resulting `stopped` event is broadcast
    # to the stream, which updates the panels. False if there's nothing to drive
    # or the command is unknown.
    def step(command)
      client = current
      method = STEP_COMMANDS[command]
      return false unless client && method

      client.public_send(method)
      true
    end

    # The panels focused on a chosen frame of the current stop. No re-execution —
    # the snapshot already carries every frame's locals. Nil when there's no stop
    # to inspect.
    def panels(frame:)
      client = current
      snapshot = client&.snapshot
      return unless snapshot

      Panels.for(client, snapshot, frame_index: frame_index(snapshot, frame))
    end

    # Stop the debuggee wherever it raises, rather than letting the exception
    # unwind into its error page. Unlike the stop-scoped calls below this works
    # while the debuggee is running — arming it mid-flight is the point.
    def break_on_exception(enabled)
      client = current
      return unless client

      client.break_on_exception = enabled
      enabled
    end

    # The children of a structured local (hash/array/object). Only meaningful
    # while stopped — the variablesReference is a handle into the current stop —
    # so a stale ref returns nil rather than an empty drill-down.
    def expand(ref)
      client = current
      return unless client&.state == :stopped && ref.to_i.positive?

      client.expand(ref.to_i)
    end

    # Evaluate an expression in the context of the selected call-stack frame. The
    # frame id (and any structured result's ref) is a handle into the current stop,
    # so away from a breakpoint we answer with a console-style error instead.
    def evaluate(expression, frame:)
      client = current
      unless client&.state == :stopped
        return {value: "not at a breakpoint — step to a stop first", ref: 0, error: true}
      end

      snapshot = client.snapshot
      client.evaluate(expression, frame_id: snapshot.dig(:frames, frame_index(snapshot, frame), :id))
    end

    def wire_callbacks(client)
      broadcaster = SessionBroadcaster.new(client)
      client.on_stop { |snapshot| broadcaster.stopped(snapshot) }
      client.on_state do |state|
        SessionRegistry.clear if state == :terminated
        broadcaster.state_changed(state)
      end
      client.on_error { |command, message| broadcaster.error(command, message) }
    end
    private_class_method :wire_callbacks

    def connect_with_retry(client, attempts: 10)
      attempts.times do |i|
        return client.connect
      rescue Errno::ECONNREFUSED
        raise if i == attempts - 1
        sleep 0.2 # server may still be opening its port
      end
    end
    private_class_method :connect_with_retry

    def frame_index(snapshot, requested)
      requested.to_i.clamp(0, [snapshot[:frames].size - 1, 0].max)
    end
    private_class_method :frame_index
  end
end
