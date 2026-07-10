module Debug
  # Bottom console: type an expression, it's evaluated in the selected call-stack
  # frame (see stepper#evaluate) and the result is appended to the log. Re-rendered
  # on every stop/resume: `stopped` gates whether it's active — resuming past the
  # breakpoint clears the log and disables input until the next stop.
  class ReplComponent < ApplicationComponent
    ID = "repl-panel".freeze

    # The log Debug::EvaluationsController appends entries to. Defined here because
    # this component renders it. (stepper_controller.js also looks it up by name.)
    OUTPUT_ID = "repl-output".freeze

    def initialize(stopped:)
      @stopped = stopped
    end

    def id = ID

    private

    attr_reader :stopped
    alias_method :stopped?, :stopped

    def output_id = OUTPUT_ID
  end
end
