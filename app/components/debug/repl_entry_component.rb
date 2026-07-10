module Debug
  # One console entry: the expression that was run and its result. A structured
  # result is rendered as a var row so it can be expanded like a local. Appended to
  # Debug::ReplComponent::OUTPUT_ID rather than owning an id of its own.
  class ReplEntryComponent < ApplicationComponent
    def initialize(expression:, result:)
      @expression = expression
      @result = result
    end

    private

    attr_reader :expression, :result

    def error? = result[:error]

    def border_class = error? ? "border-rose-700/60" : "border-slate-700/70"

    # nil when the expression can't be highlighted; the row falls back to plain text.
    def echoed
      @echoed = helpers.highlight_ruby(expression) unless defined?(@echoed)
      @echoed
    end

    def result_var
      {name: "⇒", value: result[:value], type: result[:type], ref: result[:ref]}
    end
  end
end
