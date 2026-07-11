# Cairn

A browser-based debugger that **attaches to a running Ruby app** and lets you step
through it live. It drives `rdbg` (Ruby's `debug` gem) over the Debug Adapter
Protocol: attach, trigger a request that reaches a stop, then step through frames
while inspecting the call stack, locals, and evaluating expressions in a REPL —
all from the browser.

## What's here

Three panels plus a REPL, driven over Turbo Streams:

- _center_: source at the current frame, execution line highlighted
- _right_: call stack + live locals (including instance vars), updated per stop.
  Click a frame to inspect it; expand a structured local to drill into its children
- _bottom_: step controls — continue / step over / step in / step out
- _REPL_: evaluate an expression in the selected frame while stopped

Forward stepping only — there is no recorded history or reverse execution.

## Architecture

```
Browser (Turbo Streams over ActionCable + Stimulus stepper)
      │
DebugSessionsController  +  DebugChannel (Turbo Stream relay)
      │
Debug::DapClient (plain-Ruby DAP over a socket)
      │  ▲ parked in Debug::SessionRegistry (process-global, single session)
rdbg debuggee (the app under debug, started with `rdbg --open`)
```

The controller owns the debugger directly: on `create` it opens a `Debug::DapClient`,
parks it in `Debug::SessionRegistry`, and wires callbacks that broadcast each stop
to the `debug_session` Turbo Stream. Step actions look the client up and issue
fire-and-forget execution commands; the resulting `stopped` event drives the UI.

Key files: `app/controllers/debug_sessions_controller.rb`,
`app/services/debug/dap_client.rb`, `app/services/debug/session_registry.rb`,
`app/javascript/controllers/stepper_controller.js`.

> **DAP notes** (rdbg 1.11.1): the client sends `attach {localfs: true}` so the
> target's absolute source paths map to local files (for source display).
> Execution commands are event-driven (fire-and-forget; the `stopped` event
> drives the UI).

## Running

Requires Ruby 4.0 and the `debug` gem (bundled — provides `rdbg`). There's no
database — Cairn persists nothing.

```bash
bin/setup                 # or: bundle install
bin/dev                   # or: bin/rails server
```

The compiled Tailwind CSS is committed (`app/assets/builds/tailwind.css`), so
there's no asset build to run before booting. If you change the UI, regenerate it
with `bin/rails tailwindcss:build` and commit the result — CI's
`tailwindcss:verify` fails if the commit drifts from the templates.

Start the app you want to debug under rdbg, e.g.:

```bash
rdbg --open --port 12345 --nonstop bin/rails server
```

Then open <http://localhost:3000>, fill in the host/port (and optionally the
debuggee's repo path for source display), click **Attach**, and trigger a
request that reaches a stop.

Cairn doesn't set breakpoints — stops come from the target itself: a
`binding.break` in its source, or arming the exception catchpoint (from the
session header) to stop wherever it raises.

## Notes / scope

This is a POC. `Debug::SessionRegistry` is in-memory and holds a single session
by design — the app itself persists no domain data. In development the async
ActionCable adapter shares the one Rails process so broadcasts reach the browser
without extra infra. Auth and multi-session supervision are left as future work.

## Credits

The stacked-stones logo is traced from a
<a href="https://www.flaticon.com/free-icons/spa" title="spa icons">spa icon created by Freepik — Flaticon</a>.
