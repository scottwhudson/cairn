# Tour of Changes

An interactive **PR-review tool** that lets a reviewer step through what a change
actually does *at runtime* — not just read the diff — by driving `rdbg` (Ruby's
`debug` gem) over the Debug Adapter Protocol, with narrative "waypoints" pinned
to the changed lines. See [`tour-of-changes-spec.md`](tour-of-changes-spec.md)
for the full design.

## What's here

- **Live tour** — three panels + a scrubber:
  - _left_: numbered waypoints (author-authored via `tour.yml`, or reviewer bookmarks)
  - _center_: diff-highlighted source + the "why this changed" note
  - _right_: call stack + live locals, updated per step
  - _bottom_: scrubber — step forward / over / **back** (reverse execution via
    rdbg record/replay) and scrub recorded stops without re-executing
- **Execution-trace diffing** — record two full `TracePoint` traces and diff them
  with a Myers/LCS alignment over *structural* tokens (method + call depth), so
  shifted line numbers still match. Per-step locals diffs on expand.

## Architecture

```
Browser (Turbo Streams over ActionCable + Stimulus scrubber)
      │
Rails controllers  +  DebugChannel (per-tour relay)
      │
DebugSessionJob ── Debug::DapClient (plain-Ruby DAP over a socket)
      │                     ▲ parked in Debug::SessionRegistry
rdbg debuggee (the app under review, `rdbg --open`)
```

Key files: `app/services/debug/dap_client.rb`, `app/jobs/debug_session_job.rb`,
`app/services/trace_differ.rb`, `lib/trace_recorder.rb`,
`app/javascript/controllers/scrubber_controller.js`.

> **DAP notes** (rdbg 1.11.1): the client sends `attach {localfs: true}` so
> breakpoints verify against local paths, and enables reverse debugging by
> running `,record on` via an `evaluate` request at the first stop. Execution
> commands are event-driven (fire-and-forget; the `stopped` event drives the UI).

## Running

Requires Ruby 4.0, PostgreSQL, and the `debug` gem (bundled — provides `rdbg`).

```bash
bin/setup                 # or: bundle install && bin/rails db:prepare
bin/rails db:seed         # seeds a sample tour + before/after traces
bin/rails tailwindcss:build
bin/dev                   # or: bin/rails server
```

Then open the tour printed by the seed (e.g. <http://localhost:3000/tours/1>),
click **Start session**, and use the scrubber / arrow keys (← back, → next hit,
↓ step over) to walk the change. The trace diff is linked from the seed output
and from **Trace runs**.

The sample debuggee lives in [`script/sample_app/`](script/sample_app): a volume-
discount pricing bug fix, with `pricing.rb` (after), `pricing_before.rb` (before),
and an author-authored `tour.yml`.

```bash
bin/rails trace:record    # re-record before/after execution traces
```

## Notes / scope

This is a POC. In development, `DebugSessionJob` runs in-process (`:async` adapter)
so the live `Debug::DapClient` and the async ActionCable adapter share one process
— `Debug::SessionRegistry` is in-memory and single-process by design. Auth and
multi-process session supervision are left as future work (see the spec's open
items).
