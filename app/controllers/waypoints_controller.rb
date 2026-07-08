class WaypointsController < ApplicationController
  before_action :set_tour

  # Reviewer-authored ad hoc bookmark added while exploring.
  def create
    @waypoint = @tour.waypoints.build(waypoint_params.merge(author: "reviewer"))
    if @waypoint.save
      redirect_to @tour, notice: "Bookmark added at #{@waypoint.location}."
    else
      redirect_to @tour, alert: @waypoint.errors.full_messages.to_sentence
    end
  end

  def destroy
    @tour.waypoints.find(params[:id]).destroy
    redirect_to @tour, notice: "Bookmark removed."
  end

  private

  def set_tour
    @tour = Tour.find(params[:tour_id])
  end

  def waypoint_params
    params.require(:waypoint).permit(:file, :line, :note, :condition, :change_kind)
  end
end
