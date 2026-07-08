# Tour of changes — spec

## Problem

PRs are getting bigger and automated review only goes so far. The goal is an
interactive "tour" that lets a reviewer step through what a PR actually does at
runtime — not just read the diff — using `rdbg` (Ruby's `debug` gem) to drive
real execution, with narrative context attached to each step.

## Format decision

**Web app, Rails-based.** Originally scoped as a TUI, but the requirements
(rich diff/markdown rendering, side-by-side execution-trace diffing, shareable
tours for teammates) fit a browser UI better than a terminal one. Considered
Hanami for its slice-based modularity, but rejected: the actual complexity
here is one background job driving a debugger, not many eroding domain
boundaries — and Rails' batteries (Hotwire, ActionCable, ActiveJob) map
directly onto this app's needs (live-updating panels, background debug
sessions) in a way Hanami would require hand-rolling.

## Core mechanism

`rdbg`/the `debug` gem gives us two things this tool depends on:

- **DAP support** — rdbg can run as a DAP server (`rdbg --open`, TCP or UNIX
  socket). A driver can attach as a DAP client and get structured `stopped`
  events, stack frames, and variables instead of scraping REPL text.
- **Record/replay** — `record on` plus `step back` lets you rewind through
  execution history without re-running the program. This is what makes a
  scrubber/timeline UI viable instead of a strictly forward-only session.

Breakpoints are derived from the PR's diff hunks (not every line — only
changed regions), so stepping through a tour only stops at points that
actually changed.

## Panel layout (three panels + scrubber)

- **Left — waypoints.** A numbered list of tour steps, each pinned to a
  file:line. Author-authored (shipped with the PR as YAML/JSON) or
  reviewer-authored (ad hoc bookmarks added while exploring).
- **Center — diff-highlighted source + narrative.** The changed hunk with
  added/removed lines colored, plus a "why this changed" note (commit
  message, PR description, or author-written explanation) below it.
- **Right — call stack + live locals.** Breadcrumb call stack so it's clear
  *why* a changed method got invoked, and a locals panel that updates per
  step, driven by the DAP client's variable requests.
- **Bottom — scrubber.** Step forward/back, jump to next/prev hit (for
  breakpoints inside loops), powered by rdbg's record/replay so scrubbing
  doesn't re-execute the program.

## Execution trace diffing

Separate from the live tour: the ability to record two full execution traces
(e.g. before/after a change, or two different code paths) and diff them in
the same UI.

- Don't rely on rdbg's internal trace/record buffer for this — it's
  session-scoped and not meant for export. Instead, use `TracePoint` directly
  to record a structured trace to JSONL: one event per line, with `method`,
  `file`, `line`, call `depth`, and `locals` (safely `inspect`'d).
- Key each event by structural fields (method + call depth + caller path)
  rather than raw line number, since line numbers shift between the two runs.
- Diffing two traces is a sequence-alignment problem — treat each event as a
  token and run a standard Myers/LCS diff, not a bespoke algorithm.
- UI: synced-scroll side-by-side panes (à la a split diff view), matched
  steps aligned, added/removed steps highlighted, with a per-step locals diff
  (small JSON diff) on expand.

## Architecture (Rails)

```
Browser (Hotwire: Turbo Streams + Stimulus)
        |
Rails app (controllers + one ActionCable channel: DebugChannel)
        |                                   \
ActiveJob worker (DebugSessionJob,            Database (Postgres/SQLite)
  holds a Debug::DapClient PORO that           - Tour, Waypoint
  talks DAP over a socket)                     - TraceRun (+ TraceDiffer service)
        |
rdbg debuggee (the Ruby app under review,
  running with an open DAP port)
```

- **Browser**: Turbo Frames swap the waypoint/source/context panel on
  navigation; Turbo Streams over ActionCable push live updates (new line,
  new locals, new call stack) while a session is stepping. Stimulus owns
  pure-client behavior — the scrubber, keyboard shortcuts, synced scrolling.
- **Rails app**: ordinary controllers for tour/waypoint CRUD and starting a
  session, plus `DebugChannel < ApplicationCable::Channel` that the browser
  subscribes to per tour and that just relays what the job broadcasts.
- **ActiveJob (`DebugSessionJob`)**: the one non-Rails-shaped piece. Starts
  or attaches to `rdbg --open`, owns a `Debug::DapClient` (plain Ruby over a
  socket, no extra gem needed — just JSON messages), and broadcasts to
  `DebugChannel` on each `stopped` event. Runs on Solid Queue (Rails 8,
  zero extra infra) or Sidekiq if Redis is already in use.
- **rdbg debuggee**: outside Rails entirely — just the target app or script
  running with an open debug port. Only the job talks to it.
- **Database**: plain ActiveRecord. `Tour has_many :waypoints`
  (`file`, `line`, `note`, `condition` columns). `TraceRun` points at a
  recorded JSONL trace (or stores it directly in a `jsonb` column) plus the
  git ref it was recorded against, so two runs can be diffed.
- **`TraceDiffer`**: a plain service object, not a model — pure computation
  over two `TraceRun`s, no state of its own.

Suggested directory layout:

```
app/
  channels/debug_channel.rb
  controllers/tours_controller.rb
  controllers/debug_sessions_controller.rb
  jobs/debug_session_job.rb
  models/tour.rb
  models/waypoint.rb
  models/trace_run.rb
  services/debug/dap_client.rb
  services/trace_differ.rb
  views/tours/show.turbo_stream.erb
  javascript/controllers/scrubber_controller.js
```

## Open items to design next

- `Debug::DapClient` implementation: socket handshake, `setBreakpoints`,
  `stepBack`, and `stopped`-event handling.
- `Tour`/`Waypoint` migrations and how author-authored tour files (shipped
  with a PR) get imported into them.
- The `TraceDiffer` token scheme in more detail, and the diff-view frontend
  (synced scroll + per-step locals diff).
- Auth/access model if tours are meant to be shared beyond the local
  reviewer (currently assumed to be a local/team-internal tool).
