module Debug
  # One variable row. If it's structured it gets a disclosure toggle and an empty
  # nested container that Debug::LocalsController fills on first click.
  class VarComponent < ApplicationComponent
    # Values whose whole contents are already on screen. rdbg hands back a
    # variablesReference for nearly every value, so `ref > 0` isn't enough to know
    # there's anything inside: expanding a nil or an Integer just yields an empty
    # list, and the caret promises a drill-down that never arrives.
    SCALAR_TYPES = %w[NilClass TrueClass FalseClass Integer Float Symbol].freeze

    # The container a row's children are streamed into. Defined here because this
    # component renders it; Debug::LocalsController targets it by calling this.
    # (stepper_controller.js builds the same id in JS to toggle the container.)
    def self.children_id(ref) = "var-children-#{ref.to_i}"

    def initialize(var:)
      @var = var
    end

    private

    attr_reader :var

    def name = var[:name]

    def type = var[:type]

    def ref = var[:ref]

    def children_id = self.class.children_id(ref)

    # Whether this row should offer a disclosure caret.
    def expandable?
      return false unless ref.to_i.positive?

      SCALAR_TYPES.exclude?(type.to_s)
    end

    # nil when the value can't be highlighted, so the row falls back to plain text
    # rather than blanking. Guarded rather than `||=` because nil is a real answer.
    def value_html
      @value_html = helpers.highlight_value(var[:value]) unless defined?(@value_html)
      @value_html
    end

    def value_text = value_html || var[:value]

    # `.rouge-src` hands the value over to the theme's colors; without it the
    # fallback keeps the flat emerald it had before.
    def value_class = value_html ? "rouge-src" : "text-emerald-300"
  end
end
