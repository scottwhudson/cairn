module SourceHelper
  Line = Struct.new(:number, :text, :current, keyword_init: true)

  # Reads a window of source around `focus_line` and tags each line with whether
  # it's the current execution point.
  def source_window(abs_path, focus_line, context: 8)
    return [] unless abs_path && File.file?(abs_path)

    all = File.readlines(abs_path, chomp: true)
    focus = focus_line || 1
    first = [ focus - context, 1 ].max
    last  = [ focus + context, all.size ].min

    (first..last).map do |n|
      Line.new(number: n, text: all[n - 1], current: n == focus_line)
    end
  end

  # Tailwind classes for a source line, highlighting the current execution point.
  def source_line_classes(line)
    return "bg-sky-500/20 border-l-2 border-sky-400" if line.current

    "border-l-2 border-transparent"
  end
end
