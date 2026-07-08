# Relay of debug-session updates. It subclasses Turbo::StreamsChannel so the
# browser can subscribe with `turbo_stream_from "debug_session", channel:
# "DebugChannel"` and receive the Turbo Stream broadcasts the controller pushes
# on each stop.
#
# It intentionally has no logic of its own — the controller owns the debugger and
# decides what to broadcast; this channel just carries those frames to subscribers.
class DebugChannel < Turbo::StreamsChannel
end
