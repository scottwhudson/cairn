Rails.application.routes.draw do
  # A single live debug session that attaches to a running rdbg DAP server
  # (e.g. a Rails server started with `rdbg --open`). Connect, set a breakpoint,
  # then step through the current frame as requests hit it.
  resource :debug_session, only: %i[show create destroy], controller: "debug_sessions" do
    post :step          # continue / next / step_in / step_out
    post :select_frame  # inspect a different frame of the current stop
    post :expand_local  # drill into a structured local's children
    post :evaluate      # run a REPL expression in the selected frame
    post :break_on_exception # stop at a raise instead of unwinding to the error page
  end

  get "up" => "rails/health#show", :as => :rails_health_check

  root "debug_sessions#show"
end
