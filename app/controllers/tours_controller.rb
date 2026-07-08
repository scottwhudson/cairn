class ToursController < ApplicationController
  before_action :set_tour, only: %i[show destroy import]

  def index
    @tours = Tour.order(created_at: :desc)
  end

  def show
    @waypoints = @tour.waypoints
    @client = Debug::SessionRegistry.get(@tour.id)
    @snapshot = @client&.history&.last
    @trace_runs = @tour.trace_runs.order(:created_at)
  end

  def new
    @tour = Tour.new
  end

  def create
    @tour = Tour.new(tour_params)
    if @tour.save
      import_waypoints(@tour) # pull in any author-authored tour file shipped in the repo
      redirect_to @tour, notice: "Tour created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Re-import author-authored waypoints from the tour file in the repo.
  def import
    count = import_waypoints(@tour, replace: true)
    redirect_to @tour, notice: "Imported #{count} waypoint(s) from tour file."
  rescue TourImporter::Error => e
    redirect_to @tour, alert: e.message
  end

  def destroy
    Debug::SessionRegistry.get(@tour.id)&.terminate
    @tour.destroy
    redirect_to tours_path, notice: "Tour deleted."
  end

  private

  def set_tour
    @tour = Tour.find(params[:id])
  end

  def tour_params
    params.require(:tour).permit(:title, :description, :repo_path, :entrypoint, :git_ref)
  end

  def import_waypoints(tour, replace: false)
    TourImporter.new(tour).import(replace: replace)
  rescue TourImporter::Error
    0 # no tour file shipped is fine on create
  end
end
