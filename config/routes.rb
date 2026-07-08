Rails.application.routes.draw do
  # A single live debug session that attaches to a running rdbg DAP server
  # (e.g. a Rails server started with `rdbg --open`). Connect, set a breakpoint,
  # then step through the current frame as requests hit it.
  resource :debug_session, only: %i[show create destroy], controller: "debug_sessions" do
    post :step   # continue / next / step_in / step_out / step_back
    post :scrub  # browse recorded history without re-executing
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "debug_sessions#show"
end
