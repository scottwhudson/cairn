Rails.application.routes.draw do
  resources :tours, only: %i[index show new create destroy] do
    member do
      post :import   # import author-authored tour waypoints from a YAML file
    end
    resources :waypoints, only: %i[create destroy]

    # The live debug session for a tour: start it, drive it, scrub it, stop it.
    resource :debug_session, only: %i[create destroy], controller: "debug_sessions" do
      post :step   # continue / next / step_in / step_out / step_back
      post :scrub  # browse recorded history without re-executing
    end
  end

  # Execution-trace diffing (separate from the live tour).
  resources :trace_runs, only: %i[index show]
  get "trace_diffs/:before_id/:after_id", to: "trace_diffs#show", as: :trace_diff

  get "up" => "rails/health#show", as: :rails_health_check

  root "tours#index"
end
