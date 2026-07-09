import { Controller } from "@hotwired/stimulus"

// The source pane now holds the whole file, so the stopped line is rarely in
// view on its own. Each stop re-renders the pane (a Turbo Stream update), which
// reconnects this controller — so centering on connect tracks every step.
export default class extends Controller {
  static targets = ["current"]

  connect() {
    if (this.hasCurrentTarget) {
      this.currentTarget.scrollIntoView({ block: "center" })
    }
  }
}
