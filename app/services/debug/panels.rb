module Debug
  # The stop-scoped panels of the debugger UI: which partial fills which wrapper
  # div, and the locals all of them share.
  #
  # Two callers render the same set: the controller, responding to the reviewer
  # who selected a frame, and SessionBroadcaster, pushing a new stop out to every
  # subscriber. They agree on the panels here rather than each keeping a copy.
  module Panels
    Panel = Struct.new(:partial, :target, :locals)

    # partial name => id of the wrapper div whose contents it fills.
    TARGETS = {"source" => "source-panel", "callstack" => "callstack-panel",
               "locals" => "locals-panel"}.freeze

    # A nil snapshot yields the empty/reset rendering of each panel. frame_index
    # selects which frame source/locals/callstack focus on (0 = top of stack).
    def self.for(client, snapshot, frame_index: 0)
      locals = {repo_path: client&.repo_path, snapshot: snapshot, frame_index: frame_index}
      TARGETS.map do |partial, target|
        Panel.new(partial: "debug_sessions/#{partial}", target: target, locals: locals)
      end
    end
  end
end
