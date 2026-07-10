module Debug
  # Right panel (bottom): locals for the selected frame (top frame by default).
  # Unlike the other two panels this needs no repo path — nothing here is a file
  # path — which an explicit initializer lets it say.
  class LocalsComponent < ApplicationComponent
    ID = "locals-panel".freeze

    def initialize(snapshot:, frame_index: 0)
      @snapshot = snapshot
      @frame_index = frame_index
    end

    def id = ID

    # Which frame of the stop this panel focuses on. Public because Debug::Session
    # clamps the requested frame to the stack, and the panel is where that lands.
    attr_reader :frame_index

    private

    attr_reader :snapshot

    def frame = snapshot && snapshot[:frames] && snapshot[:frames][frame_index]

    def locals
      return [] unless snapshot

      frame ? frame[:locals] : snapshot[:locals]
    end
  end
end
