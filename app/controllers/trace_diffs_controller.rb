class TraceDiffsController < ApplicationController
  def show
    @before = TraceRun.find(params[:before_id])
    @after  = TraceRun.find(params[:after_id])
    differ  = TraceDiffer.new(@before.events, @after.events)
    @rows   = differ.rows
    @stats  = differ.stats
  end
end
