module Debug
  # Which frame of the current stop the panels are focused on. A stop has exactly
  # one selection, so it's a singular resource you update rather than create.
  class SelectedFramesController < ApplicationController
    def update
      panels = Session.panels(frame: params[:frame])
      return head(:no_content) unless panels

      render turbo_stream: panels.map { |panel| turbo_stream.replace(panel.id, panel) }
    end
  end
end
