import { Controller } from "@hotwired/stimulus"

// A basic slide-over drawer. Toggle it with drawer#open / drawer#close, or by
// setting the `open` value; the backdrop and Escape close it.
export default class extends Controller {
  static targets = ["dialog", "panel", "backdrop", "autofocus"]
  static values = { open: { type: Boolean, default: false } }

  open() {
    this.openValue = true
  }

  close() {
    this.openValue = false
  }

  openValueChanged() {
    // `hidden` keeps the drawer out of the layout when closed; the transforms
    // run on the next frame so the panel animates in rather than appearing.
    if (this.openValue) this.dialogTarget.classList.remove("hidden")

    requestAnimationFrame(() => {
      this.panelTarget.classList.toggle("translate-x-full", !this.openValue)
      this.backdropTarget.classList.toggle("opacity-0", !this.openValue)
      if (this.openValue && this.hasAutofocusTarget) this.autofocusTarget.focus()
    })

    if (!this.openValue) {
      // Wait out the slide before pulling it from the layout, unless it reopened.
      setTimeout(() => {
        if (!this.openValue) this.dialogTarget.classList.add("hidden")
      }, 200)
    }
  }
}
