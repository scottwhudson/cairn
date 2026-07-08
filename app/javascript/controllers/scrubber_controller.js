import { Controller } from "@hotwired/stimulus"

// Drives the live debug session:
//   * step buttons + keyboard fire fire-and-forget execution-control commands;
//     the resulting `stopped` event is broadcast back over the session stream.
//   * the range slider scrubs recorded history — a POST that re-renders the
//     panels from a stored snapshot, without re-executing the debuggee.
export default class extends Controller {
  static targets = ["slider", "position", "bar"]
  static values = { stepUrl: String, scrubUrl: String }

  connect() {
    this.onKey = this.handleKey.bind(this)
    window.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKey)
  }

  // ── execution control (advances the debuggee) ──────────────────────
  stepBack()  { this.step("step_back") }
  stepOver()  { this.step("next") }
  stepIn()    { this.step("step_in") }
  stepOut()   { this.step("step_out") }
  continue()  { this.step("continue") }

  step(command) {
    this.post(this.stepUrlValue, { command })
  }

  // ── scrubbing (browses recorded history) ───────────────────────────
  scrub() {
    if (!this.hasSliderTarget) return
    this.post(this.scrubUrlValue, { index: this.sliderTarget.value }, /* renderStream */ true)
  }

  handleKey(event) {
    if (event.target.matches("input, textarea")) return
    const map = {
      ArrowLeft: () => this.stepBack(),
      ArrowRight: () => this.continue(),
      ArrowDown: () => this.stepOver(),
      j: () => this.scrubBy(-1),
      k: () => this.scrubBy(1),
    }
    const handler = map[event.key]
    if (handler) { event.preventDefault(); handler() }
  }

  scrubBy(delta) {
    if (!this.hasSliderTarget) return
    const next = Math.min(Math.max(Number(this.sliderTarget.value) + delta, 0), Number(this.sliderTarget.max))
    this.sliderTarget.value = next
    this.scrub()
  }

  async post(url, body, renderStream = false) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "Accept": "text/vnd.turbo-stream.html, text/html",
      },
      body: JSON.stringify(body),
    })
    if (renderStream && response.ok) {
      const text = await response.text()
      if (text.trim()) window.Turbo.renderStreamMessage(text)
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
