module IconsHelper
  # Each name must have a matching partial in app/views/shared/_icons.
  ICONS = %w[
    arrow_down
    arrow_right
    arrow_up
    bug_ant
    chevron_right
    play
  ].freeze

  # Renders a Heroicon SVG partial from app/views/shared/_icons. Icons inherit the
  # current text color (fill/stroke: currentColor) and are sized via Tailwind
  # classes, e.g. `icon("play", class: "h-4 w-4 text-white")`.
  def icon(name, class: "h-4 w-4")
    unless ICONS.include?(name.to_s)
      raise ArgumentError, "unknown icon #{name.inspect} (available: #{ICONS.join(", ")})"
    end

    render "shared/_icons/#{name}", class: binding.local_variable_get(:class)
  end
end
