module Debug
  # The stop-scoped panels of the debugger UI.
  #
  # Two callers render the same set: the controller, responding to the reviewer
  # who selected a frame, and SessionBroadcaster, pushing a new stop out to every
  # subscriber. They agree on the panels here rather than each keeping a copy.
  # Each panel is a component that knows the id it renders into, so all this has
  # to fix is the set and its order.
  module Panels
    # A nil snapshot yields the empty/reset rendering of each panel. frame_index
    # selects which frame source/locals/callstack focus on (0 = top of stack).
    def self.for(client, snapshot, frame_index: 0)
      repo_path = client&.repo_path
      [
        SourceComponent.new(snapshot:, repo_path:, frame_index:),
        CallstackComponent.new(snapshot:, repo_path:, frame_index:),
        LocalsComponent.new(snapshot:, frame_index:)
      ]
    end
  end
end
