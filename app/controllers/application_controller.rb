class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  wrap_parameters false
  stale_when_importmap_changes

  before_action :set_session

  private

  def set_session
    @session = Debug::Session.current
  end
end
