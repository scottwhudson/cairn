import { Controller } from "@hotwired/stimulus"

// Drives the live debug session: step buttons + keyboard fire fire-and-forget
// execution-control commands. The resulting `stopped` event is broadcast back
// over the session stream, which re-renders the panels.
export default class extends Controller {
  static values = {
    stepUrl: String, selectFrameUrl: String, expandLocalUrl: String, evaluateUrl: String
  }
  static targets = ["replInput"]

  connect() {
    // Which call-stack frame the REPL evaluates in. Every new stop re-renders the
    // panels focused on the top frame, so stepping resets this to 0 to match.
    this.selectedFrame = 0
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
    this.selectedFrame = 0
    this.post(this.stepUrlValue, { command })
  }

  // ── frame selection (inspects a frame of the current stop) ─────────
  selectFrame(event) {
    this.selectedFrame = event.params.frame
    this.post(this.selectFrameUrlValue, { frame: event.params.frame }, /* renderStream */ true)
  }

  // ── REPL (evaluates in the selected frame) ─────────────────────────
  async evaluate(event) {
    event.preventDefault()
    const input = this.replInputTarget
    if (input.disabled) return // no active stop
    const expression = input.value.trim()
    if (!expression) return
    input.value = ""
    await this.post(this.evaluateUrlValue, { expression, frame: this.selectedFrame }, /* renderStream */ true)
    const out = document.getElementById("repl-output")
    if (out) out.scrollTop = out.scrollHeight
  }

  // ── local expansion (drills into a structured value) ───────────────
  // Lazy-loads the value's children on first open, then just toggles
  // visibility. The ref is a handle into the current stop, so containers
  // are re-created fresh on every stop and never carry stale expansions.
  async toggleLocal(event) {
    const ref = event.params.ref
    const button = event.currentTarget
    const container = document.getElementById(`var-children-${ref}`)
    if (!container) return

    const open = button.getAttribute("aria-expanded") === "true"
    if (open) {
      container.classList.add("hidden")
      button.setAttribute("aria-expanded", "false")
      return
    }

    if (!container.dataset.loaded) {
      await this.post(this.expandLocalUrlValue, { ref }, /* renderStream */ true)
      container.dataset.loaded = "true"
    }
    container.classList.remove("hidden")
    button.setAttribute("aria-expanded", "true")
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
