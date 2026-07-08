module SourceHelper
  Line = Struct.new(:number, :text, :current, :waypoint, keyword_init: true)

  # Reads a window of source around `focus_line` and tags each line with whether
  # it's the current execution point and/or a waypoint (with its change_kind).
  # waypoints: array of Waypoint records for this file.
  def source_window(abs_path, focus_line, waypoints: [], context: 8)
    return [] unless abs_path && File.file?(abs_path)

    all = File.readlines(abs_path, chomp: true)
    focus = focus_line || 1
    first = [ focus - context, 1 ].max
    last  = [ focus + context, all.size ].min
    wp_by_line = waypoints.index_by(&:line)

    (first..last).map do |n|
      Line.new(
        number: n,
        text: all[n - 1],
        current: n == focus_line,
        waypoint: wp_by_line[n]
      )
    end
  end

  # Tailwind classes for a source line based on its change_kind / current state.
  def source_line_classes(line)
    return "bg-sky-500/20 border-l-2 border-sky-400" if line.current
    case line.waypoint&.change_kind
    when "added"    then "bg-emerald-500/10 border-l-2 border-emerald-500/60"
    when "removed"  then "bg-rose-500/10 border-l-2 border-rose-500/60"
    when "modified" then "bg-amber-500/10 border-l-2 border-amber-500/60"
    else "border-l-2 border-transparent"
    end
  end

  def change_kind_badge(kind)
    styles = {
      "added"    => "bg-emerald-500/20 text-emerald-300",
      "removed"  => "bg-rose-500/20 text-rose-300",
      "modified" => "bg-amber-500/20 text-amber-300"
    }
    kind ||= "note"
    style = styles[kind] || "bg-slate-600/30 text-slate-300"
    tag.span(kind, class: "rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide #{style}")
  end
end
