class DebugSessionsController < ApplicationController
  def show
    @snapshot = @session.snapshot
  end

  def create
    client = Debug::Session.attach(
      host: connect_params[:host], port: connect_params[:port], repo_path: connect_params[:repo_path]
    ).client
    redirect_to root_path,
      notice: "Attached to #{client.host}:#{client.port}. Trigger a request to hit the breakpoint."
  rescue Debug::Session::AlreadyAttached
    redirect_to root_path, alert: "A session is already attached. Disconnect it first."
  rescue => e
    Rails.logger.error("[DebugSession] #{e.class}: #{e.message}")
    redirect_to root_path, alert: "Could not attach: #{e.message}"
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
