class DebugSessionsController < ApplicationController
  # Turbo stream every subscriber (the show page) listens on for stop updates.
  STREAM = "debug_session".freeze

  STEP_COMMANDS = {
    "continue"  => :continue,
    "next"      => :step_over,
    "step_in"   => :step_in,
    "step_out"  => :step_out,
    "step_back" => :step_back
  }.freeze

  # partial name => dom id it replaces
  PANELS = { "source" => "source-panel", "callstack" => "callstack-panel",
             "locals" => "locals-panel", "scrubber" => "scrubber" }.freeze

  def show
    @client = Debug::SessionRegistry.get
    @snapshot = @client&.history&.last
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

  # Scrub: re-render the panels from an already-recorded stop, no re-execution.
  def scrub
    client = require_client!
    return head(:unprocessable_entity) unless client

    index = params[:index].to_i.clamp(0, [ client.history.size - 1, 0 ].max)
    snapshot = client.snapshot(index)
    return head(:no_content) unless snapshot

    render turbo_stream: panel_streams(client, snapshot, index)
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
    "#{connect_params[:host].presence || '127.0.0.1'}:#{connect_params[:port]}"
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
    client.set_breakpoints(abs, [ { line: line } ])
  end

  def wire_callbacks(client)
    client.on_stop  { |snap| broadcast_stop(client, snap) }
    client.on_state { |state| broadcast_state(state) }
    client.on_error { |cmd, msg| broadcast_flash("#{cmd} failed: #{msg}") }
  end

  # --- broadcasting ----------------------------------------------------------

  def broadcast_stop(client, snapshot)
    panel_locals(client, snapshot, snapshot[:index]).each do |partial, locals|
      Turbo::StreamsChannel.broadcast_replace_to(
        STREAM, target: PANELS[partial], partial: "debug_sessions/#{partial}", locals: locals
      )
    end
  end

  def broadcast_state(state)
    Debug::SessionRegistry.clear if state == :terminated
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM, target: "session-status", partial: "debug_sessions/status", locals: { state: state }
    )
  end

  def broadcast_flash(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM, target: "session-flash", partial: "debug_sessions/flash", locals: { message: message }
    )
  end

  # { "source" => {locals}, ... } for each panel partial.
  def panel_locals(client, snapshot, index)
    base = { repo_path: client.repo_path, snapshot: snapshot, index: index, total: client.history.size }
    PANELS.keys.index_with { base }
  end

  def panel_streams(client, snapshot, index)
    panel_locals(client, snapshot, index).map do |partial, locals|
      turbo_stream.replace(PANELS[partial], partial: "debug_sessions/#{partial}", locals: locals)
    end
  end
end
