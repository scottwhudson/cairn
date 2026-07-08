class TraceRunsController < ApplicationController
  def index
    @trace_runs = TraceRun.order(created_at: :desc)
  end

  def show
    @trace_run = TraceRun.find(params[:id])
  end
end
