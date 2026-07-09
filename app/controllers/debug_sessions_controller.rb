class DebugSessionsController < ApplicationController
  # The stepper posts JSON, which ParamsWrapper would otherwise mirror under a
  # `debug_session` key. There's no DebugSession model to filter that copy down
  # to attributes, so it duplicates every param. We read them off the top level.
  wrap_parameters false

  def show
    @client = Debug::Session.current
    @snapshot = @client&.snapshot
  end

  def create
    client = Debug::Session.attach(
      host: connect_params[:host], port: connect_params[:port], repo_path: connect_params[:repo_path]
    )
    redirect_to root_path,
      notice: "Attached to #{client.host}:#{client.port}. Trigger a request to hit the breakpoint."
  rescue Debug::Session::AlreadyAttached
    redirect_to root_path, alert: "A session is already attached. Disconnect it first."
  rescue => e
    Rails.logger.error("[DebugSession] #{e.class}: #{e.message}")
    redirect_to root_path, alert: "Could not attach: #{e.message}"
  end

  # The `stopped` event that follows is broadcast to the stream, not rendered here.
  def step
    return head(:unprocessable_entity) unless Debug::Session.step(params[:command])
    head :accepted
  end

  # Arm/disarm rdbg's catch breakpoint. Re-renders the status region so the
  # toggle reflects what the adapter actually accepted, not what was clicked.
  def break_on_exception
    client = Debug::Session.current
    return head(:unprocessable_entity) unless client

    Debug::Session.break_on_exception(ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    render turbo_stream: turbo_stream.update(
      "session-status", partial: "debug_sessions/status", locals: {state: client.state}
    )
  rescue Debug::DapClient::Error => e
    # The partial renders its own id-bearing wrapper, so replace it (as the
    # broadcaster does) rather than nesting a second one inside.
    render turbo_stream: turbo_stream.replace(
      "session-flash", partial: "debug_sessions/flash",
      locals: {message: "Could not arm exception breakpoint: #{e.message}"}
    )
  end

  # Inspect a different frame of the current stop.
  def select_frame
    panels = Debug::Session.panels(frame: params[:frame])
    return head(:no_content) unless panels

    render turbo_stream: panels.map { |panel|
      turbo_stream.update(panel.target, partial: panel.partial, locals: panel.locals)
    }
  end

  # Drill into a structured local, rendering its children into the row's nested
  # container.
  def expand_local
    children = Debug::Session.expand(params[:ref])
    return head(:no_content) unless children

    render turbo_stream: turbo_stream.update(
      "var-children-#{params[:ref].to_i}", partial: "debug_sessions/vars", locals: {vars: children}
    )
  end

  # REPL: evaluate an expression in the selected frame and append the result to
  # the console log.
  def evaluate
    expression = params[:expression].to_s.strip
    return head(:no_content) if expression.blank?

    result = Debug::Session.evaluate(expression, frame: params[:frame])
    render turbo_stream: turbo_stream.append(
      "repl-output", partial: "debug_sessions/repl_entry",
      locals: {expression: expression, result: result}
    )
  end

  def destroy
    Debug::Session.detach
    redirect_to root_path, notice: "Detached. Your server keeps running."
  end

  private

  def connect_params
    params.fetch(:debug_session, {}).permit(:host, :port, :repo_path)
  end
end
