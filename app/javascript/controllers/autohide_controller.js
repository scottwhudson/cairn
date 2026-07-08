import { Controller } from "@hotwired/stimulus"

// Fades out a transient flash message after a delay.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timer = setTimeout(() => {
      this.element.style.transition = "opacity 0.4s"
      this.element.style.opacity = "0"
      setTimeout(() => this.element.remove(), 400)
    }, this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
