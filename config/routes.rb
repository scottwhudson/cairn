Rails.application.routes.draw do
  # A single live debug session that attaches to a running rdbg DAP server
  # (e.g. a Rails server started with `rdbg --open`). Connect, set a breakpoint,
  # then step through the current frame as requests hit it.
  #
  # Everything you do at a stop is a resource of that session rather than a verb
  # on it: a step is created, the selected frame is updated, a local is read.
  resource :debug_session, only: %i[show create destroy], controller: "debug_sessions" do
    scope module: :debug do
      resources :steps, only: :create              # continue / next / step_in / step_out
      resources :locals, only: :show               # drill into a structured local's children
      resources :evaluations, only: :create        # run a REPL expression in the selected frame
      resource :selected_frame, only: :update      # inspect a different frame of the current stop
      resource :exception_breakpoint, only: %i[create destroy] # stop at a raise instead of unwinding
    end
  end

  get "up" => "rails/health#show", :as => :rails_health_check

  root "debug_sessions#show"
end
