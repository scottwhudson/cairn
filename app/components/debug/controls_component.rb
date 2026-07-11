module Debug
  # Execution controls. Rendered into the source panel's header, above the code
  # they step through. Ghost buttons: the icon carries the meaning, the label stays
  # quiet until hover. Continue is set apart by a rule and an accent.
  class ControlsComponent < ApplicationComponent
    private

    def step_classes
      "inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs text-zinc-400 transition-colors " \
        "hover:bg-zinc-800 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-1 " \
        "focus-visible:ring-zinc-600"
    end
  end
end
