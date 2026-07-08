import { Controller } from "@hotwired/stimulus"

// Enables the "diff these two" link once a before + after trace are both chosen.
export default class extends Controller {
  static targets = ["link"]

  update() {
    const before = this.element.querySelector("input[name=before_id]:checked")?.value
    const after = this.element.querySelector("input[name=after_id]:checked")?.value
    if (before && after) {
      this.linkTarget.href = `/trace_diffs/${before}/${after}`
      this.linkTarget.classList.remove("pointer-events-none", "opacity-50", "bg-slate-700", "text-slate-400")
      this.linkTarget.classList.add("bg-sky-600", "text-white")
      this.linkTarget.textContent = "Diff these two →"
    }
  }
}
