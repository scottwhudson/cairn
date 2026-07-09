import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "cairn:app-frames-only"

// Hides gem and framework frames from the call stack, leaving the code under
// debug. Filtering is done here rather than server-side because every stop
// re-renders this panel: the preference has to outlive the markup, so it lives
// in localStorage and is re-applied on each connect.
//
// Hiding never renumbers anything — each frame keeps the index the server gave
// it, so selecting a frame still addresses the right one in the snapshot.
export default class extends Controller {
  static targets = ["toggle", "frame", "empty"]

  connect() {
    this.appOnly = localStorage.getItem(STORAGE_KEY) === "true"
    this.render()
  }

  toggle() {
    this.appOnly = !this.appOnly
    localStorage.setItem(STORAGE_KEY, this.appOnly)
    this.render()
  }

  render() {
    let shown = 0

    this.frameTargets.forEach((frame) => {
      // The selected frame always stays: the locals pane is showing its
      // variables, and hiding the row it belongs to reads as a bug.
      const filtered = this.appOnly && frame.dataset.app !== "true"
      const hidden = filtered && frame.dataset.selected !== "true"

      frame.classList.toggle("hidden", hidden)
      if (!hidden) shown += 1
    })

    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-pressed", String(this.appOnly))
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", shown > 0)
  }
}
