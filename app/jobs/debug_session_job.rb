require "socket"

# Launches (or attaches to) an rdbg DAP server for a Tour, wires a Debug::DapClient
# to it, and parks the client in Debug::SessionRegistry so controller step actions
# can drive it. Every `stopped` event is broadcast to the tour's Turbo stream.
#
# This is the one non-Rails-shaped piece: it holds a long-lived socket connection
# and outlives its own #perform (the client's reader/dispatcher threads keep
# running). In dev this runs in-process via the :async adapter, so the async
# ActionCable adapter's broadcasts reach the browser.
class DebugSessionJob < ApplicationJob
  queue_as :default

  def perform(tour_id)
    tour = Tour.find(tour_id)
    return if Debug::SessionRegistry.active?(tour.id)

    tour.update_status!("starting")
    port = free_port
    pid = spawn_rdbg(tour, port)

    client = Debug::DapClient.new(
      host: "127.0.0.1", port: port, logger: Rails.logger,
      waypoint_resolver: waypoint_resolver(tour)
    )
    client.debuggee_pid = pid

    wire_callbacks(client, tour)

    connect_with_retry(client)
    set_breakpoints(client, tour)
    client.configuration_done

    Debug::SessionRegistry.put(tour.id, client)
    tour.update_status!("running")
  rescue => e
    Rails.logger.error("[DebugSessionJob] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    tour&.update_status!("errored")
    broadcast_flash(tour, "Could not start debug session: #{e.message}") if tour
    Debug::SessionRegistry.delete(tour.id) if tour
  end

  private

  # rdbg stops at load and waits for our connection; --sock-path unused, we use TCP.
  def spawn_rdbg(tour, port)
    cmd = [ "rdbg", "--open", "--port", port.to_s, tour.entrypoint_path ]
    Rails.logger.info("[DebugSessionJob] spawning: #{cmd.join(' ')} (cwd=#{tour.repo_path})")
    Process.spawn(*cmd, chdir: tour.repo_path, out: rdbg_log(tour), err: [ :child, :out ])
  end

  def rdbg_log(tour)
    path = Rails.root.join("log", "rdbg-tour-#{tour.id}.log")
    File.open(path, "a")
  end

  def connect_with_retry(client, attempts: 25)
    attempts.times do |i|
      return client.connect
    rescue Errno::ECONNREFUSED
      sleep 0.2 # rdbg is still opening its port
      raise if i == attempts - 1
    end
  end

  def set_breakpoints(client, tour)
    tour.breakpoints_by_file.each do |abs_path, bps|
      client.set_breakpoints(abs_path, bps)
    end
  end

  # Maps a stopped file:line back to the waypoint whose breakpoint produced it,
  # so the UI can surface that waypoint's narrative.
  def waypoint_resolver(tour)
    index = {}
    tour.waypoints.each { |w| index[[ w.absolute_path, w.line ]] = w.id }
    ->(file, line) { index[[ file, line ]] }
  end

  def wire_callbacks(client, tour)
    client.on_stop  { |snap| broadcast_stop(tour, client, snap) }
    client.on_state { |state| broadcast_state(tour, state) }
    client.on_error { |cmd, msg| broadcast_flash(tour, "#{cmd} failed: #{msg}") }
  end

  # --- broadcasting ---------------------------------------------------------

  def broadcast_stop(tour, client, snapshot)
    locals = { tour: tour, snapshot: snapshot, index: snapshot[:index], total: client.history.size }
    Turbo::StreamsChannel.broadcast_replace_to(tour, target: "source-panel",    partial: "debug_sessions/source",    locals: locals)
    Turbo::StreamsChannel.broadcast_replace_to(tour, target: "callstack-panel", partial: "debug_sessions/callstack", locals: locals)
    Turbo::StreamsChannel.broadcast_replace_to(tour, target: "locals-panel",    partial: "debug_sessions/locals",    locals: locals)
    Turbo::StreamsChannel.broadcast_replace_to(tour, target: "scrubber",        partial: "debug_sessions/scrubber",  locals: locals)
  end

  def broadcast_state(tour, state)
    tour.update_status!(state.to_s) if Tour::STATUSES.include?(state.to_s)
    Turbo::StreamsChannel.broadcast_replace_to(
      tour, target: "session-status", partial: "debug_sessions/status", locals: { tour: tour, state: state }
    )
    Debug::SessionRegistry.delete(tour.id) if state == :terminated
  end

  def broadcast_flash(tour, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      tour, target: "session-flash", partial: "debug_sessions/flash", locals: { message: message }
    )
  end

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end
end
