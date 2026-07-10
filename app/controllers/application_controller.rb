class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # The stepper posts JSON, which ParamsWrapper would otherwise mirror under a
  # key named for the controller. There's no model behind those controllers to
  # filter the copy down to attributes, so it duplicates every param. We read
  # them off the top level.
  wrap_parameters false

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
