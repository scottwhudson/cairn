module Debug
  # REPL: evaluating an expression in the selected frame creates an entry, which
  # is appended to the console log.
  class EvaluationsController < ApplicationController
    def create
      expression = params[:expression].to_s.strip
      return head(:no_content) if expression.blank?

      result = @session.evaluate(expression, frame: params[:frame])
      render turbo_stream: turbo_stream.append(
        ReplComponent::OUTPUT_ID, ReplEntryComponent.new(expression: expression, result: result)
      )
    end
  end
end
