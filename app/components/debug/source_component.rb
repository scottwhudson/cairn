module Debug
  # Center panel: source at the selected frame (top frame by default). Fills its
  # grid cell as a column — pinned title + controls header, scrolling code, pinned
  # footer naming the file on screen.
  class SourceComponent < ApplicationComponent
    ID = "source-panel".freeze

    # A nil snapshot is the detached/resumed rendering: no frame, no source.
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

    def frame = snapshot && snapshot[:frames] && snapshot[:frames][frame_index]

    def abs_path = frame ? frame[:file] : snapshot && snapshot[:file]

    def focus_line = frame ? frame[:line] : snapshot && snapshot[:line]

    def lines = @lines ||= helpers.source_lines(abs_path, focus_line)

    def rel_path
      return abs_path unless abs_path && repo_path.present?

      abs_path.sub("#{repo_path}/", "")
    end

    def raised? = snapshot[:reason].to_s == "exception"

    def reason_classes
      raised? ? "bg-rose-500/20 text-rose-300" : "bg-red-500/20 text-red-300"
    end
  end
end
