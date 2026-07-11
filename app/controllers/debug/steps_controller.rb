module Debug
  # Driving execution creates a step. Fire-and-forget: the `stopped` event that
  # follows is broadcast to the stream, not rendered here.
  class StepsController < ApplicationController
    def create
      return head(:unprocessable_entity) unless @session.step(params[:command])
      head :accepted
    end
  end
end
