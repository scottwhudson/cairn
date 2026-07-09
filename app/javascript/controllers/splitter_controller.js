import { Controller } from "@hotwired/stimulus"

// A drag handle sitting between two panels of a CSS grid. The grid sizes one of
// its tracks from a custom property (e.g. `--side-w`); dragging rewrites that
// property, so the neighbouring `1fr` track absorbs the difference.
//
// `edge` names the side of the grid that the sized track is anchored to, which
// is what turns a pointer position into a track size. A handle to the *left* of
// a right-anchored sidebar has edge "right": the sidebar is as wide as the gap
// between the pointer and the grid's right edge.
//
// Sizes persist per `storageKey`, so a layout survives reload — matching the
// IDEs this pane arrangement is borrowed from.
export default class extends Controller {
  static values = {
    variable: String,
    edge: String,
    min: { type: Number, default: 120 },
    max: { type: Number, default: Infinity },
    storageKey: String,
  }

  connect() {
    this.grid = this.element.parentElement
    this.vertical = this.edgeValue === "top" || this.edgeValue === "bottom"

    const saved = this.#read()
    if (saved) this.#apply(saved)

    // Bound once so removeEventListener in `disconnect` matches, and so a drag
    // that ends outside the window still tears down its listeners.
    this.onMove = this.#onMove.bind(this)
    this.onUp = this.#onUp.bind(this)
  }

  disconnect() {
    this.#stopListening()
  }

  start(event) {
    event.preventDefault() // Otherwise the pointer selects source text mid-drag.
    window.addEventListener("pointermove", this.onMove)
    window.addEventListener("pointerup", this.onUp)
    window.addEventListener("pointercancel", this.onUp)
    document.body.classList.add(this.vertical ? "cursor-row-resize" : "cursor-col-resize", "select-none")
  }

  // Double-click a handle to drop back to the stylesheet's default size.
  reset() {
    this.grid.style.removeProperty(this.variableValue)
    if (this.hasStorageKeyValue) localStorage.removeItem(this.storageKeyValue)
  }

  #onMove(event) {
    const rect = this.grid.getBoundingClientRect()
    const size = {
      left: event.clientX - rect.left,
      right: rect.right - event.clientX,
      top: event.clientY - rect.top,
      bottom: rect.bottom - event.clientY,
    }[this.edgeValue]

    // Never let a panel grow so far that its neighbour drops below `min`.
    const span = this.vertical ? rect.height : rect.width
    const ceiling = Math.min(this.maxValue, span - this.minValue)
    this.#apply(Math.round(Math.max(this.minValue, Math.min(ceiling, size))))
  }

  #onUp() {
    this.#stopListening()
    const size = this.grid.style.getPropertyValue(this.variableValue)
    if (size && this.hasStorageKeyValue) localStorage.setItem(this.storageKeyValue, size)
  }

  #stopListening() {
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
    window.removeEventListener("pointercancel", this.onUp)
    document.body.classList.remove("cursor-row-resize", "cursor-col-resize", "select-none")
  }

  #apply(size) {
    this.grid.style.setProperty(this.variableValue, typeof size === "number" ? `${size}px` : size)
  }

  #read() {
    return this.hasStorageKeyValue ? localStorage.getItem(this.storageKeyValue) : null
  }
}
