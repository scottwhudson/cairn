module Debug
  # Right panel (top): call stack at the current stop. Click a frame to inspect it.
  # The all/app/non-app filter narrows which frames show — see frame_filter.
  class CallstackComponent < ApplicationComponent
    ID = "callstack-panel".freeze

    def initialize(snapshot:, repo_path:, frame_index: 0)
      @snapshot = snapshot
      @repo_path = repo_path
      @frame_index = frame_index
    end

    def id = ID

    # Which frame of the stop this panel focuses on. Public because Debug::Session
    # clamps the requested frame to the stack, and the panel is where that lands.
    attr_reader :frame_index

    private

    attr_reader :snapshot, :repo_path

    def frames = snapshot ? snapshot[:frames] : []

    # With no repo root nothing classifies as an app frame, so the filter would
    # blank the pane. Offer it only when app code can be told from gem code.
    def filterable? = repo_path.present? && frames.present?

    def selected?(index) = index == frame_index

    def app_frame?(frame) = DapClient.app_frame?(frame[:file], repo_path)

    def rel_path(frame)
      return frame[:file].to_s unless repo_path.present?

      frame[:file].to_s.sub("#{repo_path}/", "")
    end

    def frame_classes(index)
      base = "flex w-full items-baseline gap-2 rounded px-2 py-1 text-left "
      base + (selected?(index) ? "bg-zinc-800" : "hover:bg-zinc-800/50")
    end
  end
end
