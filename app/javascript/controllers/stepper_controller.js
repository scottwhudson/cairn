import { Controller } from "@hotwired/stimulus"

// Drives the live debug session: step buttons + keyboard fire fire-and-forget
// execution-control commands. The resulting `stopped` event is broadcast back
// over the session stream, which re-renders the panels.
export default class extends Controller {
  static values = { stepUrl: String, selectFrameUrl: String }

  connect() {
    this.onKey = this.handleKey.bind(this)
    window.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKey)
  }

  // ── execution control (advances the debuggee) ──────────────────────
  stepOver()  { this.step("next") }
  stepIn()    { this.step("step_in") }
  stepOut()   { this.step("step_out") }
  continue()  { this.step("continue") }

  step(command) {
    this.post(this.stepUrlValue, { command })
  }

  // ── frame selection (inspects a frame of the current stop) ─────────
  selectFrame(event) {
    this.post(this.selectFrameUrlValue, { frame: event.params.frame }, /* renderStream */ true)
  }

  handleKey(event) {
    if (event.target.matches("input, textarea")) return
    const map = {
      ArrowRight: () => this.continue(),
      ArrowDown: () => this.stepOver(),
      ArrowUp: () => (event.shiftKey ? this.stepOut() : this.stepIn()),
    }
    const handler = map[event.key]
    if (handler) { event.preventDefault(); handler() }
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
