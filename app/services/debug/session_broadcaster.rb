module Debug
  # Pushes debug-session updates to every subscriber of the show page.
  #
  # The DapClient's dispatcher thread drives this from outside any request, so it
  # broadcasts rather than renders: a stop that arrives seconds after the step
  # request returned still lands on the page.
  class SessionBroadcaster
    # Turbo stream every subscriber (the show page) listens on.
    STREAM = "debug_session".freeze

    def initialize(client, stream: STREAM)
      @client = client
      @stream = stream
    end

    # Execution stopped: repopulate the panels and reactivate the console.
    def stopped(snapshot)
      broadcast_panels(snapshot)
      broadcast_repl(stopped: true)
    end

    def state_changed(state)
      # Execution resumed or ended: blank the panels so they don't keep showing the
      # frame we just left, and reset the REPL (its refs/frame are now stale). A
      # following `stopped` repopulates the panels and reactivates the console.
      if %i[running terminated].include?(state)
        broadcast_panels(nil)
        broadcast_repl(stopped: false)
      end
      broadcast_update("session-status", "status", state: state)
    end

    def error(command, message)
      Turbo::StreamsChannel.broadcast_replace_to(
        @stream, target: "session-flash", partial: "debug_sessions/flash",
        locals: {message: "#{command} failed: #{message}"}
      )
    end

    private

    # `update` (not `replace`) so the id-bearing wrapper div survives — replacing it
    # strips the id, and the next broadcast (e.g. the reset on resume) can't find its
    # target and silently no-ops, leaving the stale frame on screen.
    def broadcast_panels(snapshot)
      Panels.for(@client, snapshot).each do |panel|
        Turbo::StreamsChannel.broadcast_update_to(
          @stream, target: panel.target, partial: panel.partial, locals: panel.locals
        )
      end
    end

    # Re-render the whole REPL region. `update` keeps the id-bearing wrapper, and
    # re-rendering clears the log — so exiting a stop wipes stale entries and
    # disables input until the next stop reactivates it.
    def broadcast_repl(stopped:)
      broadcast_update("repl-panel", "repl", stopped: stopped)
    end

    def broadcast_update(target, partial, **locals)
      Turbo::StreamsChannel.broadcast_update_to(
        @stream, target: target, partial: "debug_sessions/#{partial}", locals: locals
      )
    end
  end
end
