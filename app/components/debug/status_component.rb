module Debug
  # Session state pill + break-on-exception + attach/detach control.
  class StatusComponent < ApplicationComponent
    ID = "session-status".freeze

    STATE_COLORS = {
      "running" => "bg-emerald-500", "connected" => "bg-emerald-500",
      "stopped" => "bg-amber-400", "starting" => "bg-amber-400 animate-pulse",
      "terminated" => "bg-zinc-500"
    }.freeze

    # `client` is nil while detached, and is passed in rather than read back from
    # Debug::Session. The broadcaster renders this from the dispatcher thread, so
    # a global lookup would report whatever happened to be current when the
    # template ran, not the session the `state` we were handed belongs to.
    def initialize(state:, client:)
      @state = state
      @client = client
    end

    def id = ID

    private

    attr_reader :state, :client

    def attached? = client.present?

    def armed? = client&.break_on_exception || false

    def state_color = STATE_COLORS.fetch(state.to_s, "bg-zinc-600")

    def toggle_classes
      "rounded px-2 py-1 text-xs font-medium transition-colors " +
        if armed?
          "bg-rose-500/15 text-rose-300 hover:bg-rose-500/25"
        else
          "text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200"
        end
    end
  end
end
