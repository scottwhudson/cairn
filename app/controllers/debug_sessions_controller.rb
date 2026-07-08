class DebugSessionsController < ApplicationController
  before_action :set_tour

  STEP_COMMANDS = {
    "continue"  => :continue,
    "next"      => :step_over,
    "step_in"   => :step_in,
    "step_out"  => :step_out,
    "step_back" => :step_back
  }.freeze

  # Start a session: enqueue the job that launches rdbg and attaches a client.
  def create
    DebugSessionJob.perform_later(@tour.id) unless Debug::SessionRegistry.active?(@tour.id)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: status_stream("starting") }
      format.html { redirect_to @tour }
    end
  end

  # Drive execution. Fire-and-forget: the resulting `stopped` event is broadcast
  # to the tour stream, which updates the panels.
  def step
    client = require_client!
    method = STEP_COMMANDS[params[:command]]
    return head(:unprocessable_entity) unless client && method

    client.public_send(method)
    head :accepted
  end

  # Scrub: browse an already-recorded stop by history index. No re-execution —
  # we just re-render the panels from the stored snapshot.
  def scrub
    client = require_client!
    return head(:unprocessable_entity) unless client

    index = params[:index].to_i.clamp(0, [ client.history.size - 1, 0 ].max)
    snapshot = client.snapshot(index)
    return head(:no_content) unless snapshot

    render turbo_stream: snapshot_streams(snapshot, index, client.history.size)
  end

  def destroy
    Debug::SessionRegistry.get(@tour.id)&.terminate
    @tour.update_status!("stopped")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: status_stream("stopped") }
      format.html { redirect_to @tour }
    end
  end

  private

  def set_tour
    @tour = Tour.find(params[:tour_id])
  end

  def require_client!
    Debug::SessionRegistry.get(@tour.id)
  end

  def status_stream(state)
    turbo_stream.replace("session-status",
      partial: "debug_sessions/status", locals: { tour: @tour, state: state })
  end

  # partial name => dom id it replaces
  PANELS = { "source" => "source-panel", "callstack" => "callstack-panel",
             "locals" => "locals-panel", "scrubber" => "scrubber" }.freeze

  def snapshot_streams(snapshot, index, total)
    locals = { tour: @tour, snapshot: snapshot, index: index, total: total }
    PANELS.map do |partial, dom_id|
      turbo_stream.replace(dom_id, partial: "debug_sessions/#{partial}", locals: locals)
    end
  end
end
