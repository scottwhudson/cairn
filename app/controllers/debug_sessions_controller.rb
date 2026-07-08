class DebugSessionsController < ApplicationController
  # Turbo stream every subscriber (the show page) listens on for stop updates.
  STREAM = "debug_session".freeze

  STEP_COMMANDS = {
    "continue" => :continue,
    "next" => :step_over,
    "step_in" => :step_in,
    "step_out" => :step_out
  }.freeze

  # partial name => id of the wrapper div whose contents it fills. All are
  # re-rendered on every stop, and blanked when execution resumes.
  PANELS = {"source" => "source-panel", "callstack" => "callstack-panel",
            "locals" => "locals-panel"}.freeze

  def show
    @client = Debug::SessionRegistry.get
    @snapshot = @client&.snapshot
  end

  # Attach to a running rdbg DAP server (e.g. a Rails server started with
  # `rdbg --open`), optionally set a breakpoint, then wait for it to be hit.
  def create
    if Debug::SessionRegistry.active?
      return redirect_to(root_path, alert: "A session is already attached. Disconnect it first.")
    end

    client = Debug::DapClient.new(
      host: connect_params[:host].presence || "127.0.0.1",
      port: connect_params[:port].to_i,
      logger: Rails.logger,
      repo_path: connect_params[:repo_path].presence
    )
    wire_callbacks(client)

    connect_with_retry(client)
    set_breakpoint(client)
    client.configuration_done
    Debug::SessionRegistry.put(client)

    redirect_to root_path, notice: "Attached to #{client_target}. Trigger a request to hit the breakpoint."
  rescue => e
    Rails.logger.error("[DebugSession] #{e.class}: #{e.message}")
    redirect_to root_path, alert: "Could not attach: #{e.message}"
  end

  # Drive execution. Fire-and-forget: the resulting `stopped` event is broadcast
  # to the stream, which updates the panels.
  def step
    client = require_client!
    method = STEP_COMMANDS[params[:command]]
    return head(:unprocessable_entity) unless client && method

    client.public_send(method)
    head :accepted
  end

  # Inspect a different frame of the current stop: re-render the source, locals
  # and call-stack panels focused on the chosen frame. No re-execution — the
  # snapshot already carries every frame's locals.
  def select_frame
    client = require_client!
    snapshot = client&.snapshot
    return head(:no_content) unless snapshot

    frame_index = params[:frame].to_i.clamp(0, [snapshot[:frames].size - 1, 0].max)
    render turbo_stream: panel_streams(client, snapshot, frame_index)
  end

  # Drill into a structured local (hash/array/object): fetch its children from
  # the adapter and render them into the row's nested container. Only meaningful
  # while stopped — the variablesReference is a handle into the current stop.
  def expand_local
    client = require_client!
    ref = params[:ref].to_i
    return head(:no_content) unless client&.state == :stopped && ref.positive?

    children = client.expand(ref)
    render turbo_stream: turbo_stream.update(
      "var-children-#{ref}", partial: "debug_sessions/vars", locals: {vars: children}
    )
  end

  # REPL: evaluate an expression in the context of the selected call-stack frame
  # and append the result to the console log. Only meaningful while stopped — the
  # frame id (and any structured result's ref) is a handle into the current stop.
  def evaluate
    client = require_client!
    expr = params[:expression].to_s.strip
    return head(:no_content) if expr.blank?

    result =
      if client&.state == :stopped
        snapshot = client.snapshot
        idx = params[:frame].to_i.clamp(0, [snapshot[:frames].size - 1, 0].max)
        client.evaluate(expr, frame_id: snapshot.dig(:frames, idx, :id))
      else
        {value: "not at a breakpoint — step to a stop first", ref: 0, error: true}
      end

    render turbo_stream: turbo_stream.append(
      "repl-output", partial: "debug_sessions/repl_entry",
      locals: {expression: expr, result: result}
    )
  end

  def destroy
    Debug::SessionRegistry.get&.detach
    Debug::SessionRegistry.clear
    redirect_to root_path, notice: "Detached. Your server keeps running."
  end

  private

  def connect_params
    params.fetch(:debug_session, {}).permit(:host, :port, :repo_path, :file, :line)
  end

  def require_client!
    Debug::SessionRegistry.get
  end

  def client_target
    "#{connect_params[:host].presence || "127.0.0.1"}:#{connect_params[:port]}"
  end

  def connect_with_retry(client, attempts: 10)
    attempts.times do |i|
      return client.connect
    rescue Errno::ECONNREFUSED
      raise if i == attempts - 1
      sleep 0.2 # server may still be opening its port
    end
  end

  def set_breakpoint(client)
    file = connect_params[:file].presence
    line = connect_params[:line].to_i
    return unless file && line.positive?

    abs = File.expand_path(file, client.repo_path)
    client.set_breakpoints(abs, [{line: line}])
  end

  def wire_callbacks(client)
    client.on_stop { |snap| broadcast_stop(client, snap) }
    client.on_state { |state| broadcast_state(client, state) }
    client.on_error { |cmd, msg| broadcast_flash("#{cmd} failed: #{msg}") }
  end

  # --- broadcasting ----------------------------------------------------------

  def broadcast_stop(client, snapshot)
    broadcast_panels(client, snapshot)
    broadcast_repl(stopped: true)
  end

  def broadcast_state(client, state)
    Debug::SessionRegistry.clear if state == :terminated
    # Execution resumed or ended: blank the panels so they don't keep showing the
    # frame we just left, and reset the REPL (its refs/frame are now stale). A
    # following `stopped` repopulates the panels and reactivates the console.
    if %i[running terminated].include?(state)
      broadcast_panels(client, nil)
      broadcast_repl(stopped: false)
    end
    Turbo::StreamsChannel.broadcast_update_to(
      STREAM, target: "session-status", partial: "debug_sessions/status", locals: {state: state}
    )
  end

  # Broadcast every panel from a snapshot (nil snapshot => empty/reset state).
  # `update` (not `replace`) so the id-bearing wrapper div survives — replacing it
  # strips the id, and the next broadcast (e.g. the reset on resume) can't find its
  # target and silently no-ops, leaving the stale frame on screen.
  def broadcast_panels(client, snapshot)
    panel_locals(client, snapshot).each do |partial, locals|
      Turbo::StreamsChannel.broadcast_update_to(
        STREAM, target: PANELS[partial], partial: "debug_sessions/#{partial}", locals: locals
      )
    end
  end

  # Re-render the whole REPL region. `update` keeps the id-bearing wrapper, and
  # re-rendering clears the log — so exiting a stop wipes stale entries and
  # disables input until the next stop reactivates it.
  def broadcast_repl(stopped:)
    Turbo::StreamsChannel.broadcast_update_to(
      STREAM, target: "repl-panel", partial: "debug_sessions/repl", locals: {stopped: stopped}
    )
  end

  def broadcast_flash(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM, target: "session-flash", partial: "debug_sessions/flash", locals: {message: message}
    )
  end

  # { "source" => {locals}, ... } for each panel partial. frame_index selects
  # which frame the source/locals/callstack panels focus on (0 = top of stack).
  def panel_locals(client, snapshot, frame_index = 0)
    base = {repo_path: client.repo_path, snapshot: snapshot, frame_index: frame_index}
    PANELS.keys.index_with { base }
  end

  def panel_streams(client, snapshot, frame_index = 0)
    panel_locals(client, snapshot, frame_index).map do |partial, locals|
      turbo_stream.update(PANELS[partial], partial: "debug_sessions/#{partial}", locals: locals)
    end
  end
end
