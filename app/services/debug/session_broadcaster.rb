module Debug
  # Pushes debug-session updates to every subscriber of the show page.
  #
  # The DapClient's dispatcher thread drives this from outside any request, so it
  # broadcasts rather than renders: a stop that arrives seconds after the step
  # request returned still lands on the page.
  #
  # Every region is a component that owns the id it renders, so nothing here names
  # a dom id or a partial: this decides *what* to repaint, and each component
  # knows *where*.
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
      StatusComponent.new(state: state, client: @client).broadcast_replace_to(@stream)
    end

    def error(command, message)
      FlashComponent.new(message: "#{command} failed: #{message}").broadcast_replace_to(@stream)
    end

    private

    def broadcast_panels(snapshot)
      Panels.for(@client, snapshot).each { |panel| panel.broadcast_replace_to(@stream) }
    end

    # Re-render the whole REPL region. Re-rendering clears the log, so exiting a
    # stop wipes stale entries and disables input until the next stop reactivates it.
    def broadcast_repl(stopped:)
      ReplComponent.new(stopped: stopped).broadcast_replace_to(@stream)
    end
  end
end
