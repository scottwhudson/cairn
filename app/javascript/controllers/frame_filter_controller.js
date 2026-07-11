import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "cairn:frame-filter"
const MODES = ["all", "app", "non-app"]

// Filters the call stack to a chosen slice of frames:
//   - all:     every frame
//   - app:     only the code under debug (application frames)
//   - non-app: only frames from gems and the framework
//
// Filtering is done here rather than server-side because every stop re-renders
// this panel: the preference has to outlive the markup, so it lives in
// localStorage and is re-applied on each connect.
//
// Hiding never renumbers anything — each frame keeps the index the server gave
// it, so selecting a frame still addresses the right one in the snapshot.
export default class extends Controller {
  static targets = ["button", "frame", "empty"]

  connect() {
    const saved = localStorage.getItem(STORAGE_KEY)
    this.mode = MODES.includes(saved) ? saved : "all"
    this.render()
  }

  select(event) {
    const mode = event.currentTarget.dataset.mode
    if (!MODES.includes(mode)) return

    this.mode = mode
    localStorage.setItem(STORAGE_KEY, mode)
    this.render()
  }

  render() {
    let shown = 0

    this.frameTargets.forEach((frame) => {
      const isApp = frame.dataset.app === "true"
      const matches =
        this.mode === "all" ||
        (this.mode === "app" && isApp) ||
        (this.mode === "non-app" && !isApp)

      // The selected frame always stays: the locals pane is showing its
      // variables, and hiding the row it belongs to reads as a bug.
      const hidden = !matches && frame.dataset.selected !== "true"

      frame.classList.toggle("hidden", hidden)
      if (!hidden) shown += 1
    })

    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.mode === this.mode))
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", shown > 0)
  }
}
