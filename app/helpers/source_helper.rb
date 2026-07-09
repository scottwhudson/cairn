require "rouge"

module SourceHelper
  Line = Struct.new(:number, :text, :html, :current)

  # Reads a window of source around `focus_line` and tags each line with whether
  # it's the current execution point. Each line also carries Rouge-highlighted
  # HTML (`html`); callers fall back to `text` when highlighting is unavailable.
  def source_window(abs_path, focus_line, context: 8)
    return [] unless abs_path && File.file?(abs_path)

    source = File.read(abs_path)
    text_lines = source.split("\n", -1)
    # split's trailing "" from a final newline isn't a real line — drop it so the
    # line count matches File.readlines.
    text_lines.pop if text_lines.size > 1 && text_lines.last == ""
    html_lines = highlighted_lines(abs_path, source)

    focus = focus_line || 1
    first = [focus - context, 1].max
    last = [focus + context, text_lines.size].min

    (first..last).map do |n|
      Line.new(number: n, text: text_lines[n - 1], html: html_lines[n - 1], current: n == focus_line)
    end
  end

  # Tailwind classes for a source line, highlighting the current execution point.
  def source_line_classes(line)
    return "bg-sky-500/20 border-l-2 border-sky-400" if line.current

    "border-l-2 border-transparent"
  end

  # The Rouge theme CSS, scoped to `.rouge-src` (the class on each source `<code>`
  # element). Memoized per process — the theme never changes. The base rule paints
  # a dark background we don't want inside the pane, so it's overridden to blend in.
  def source_theme_css
    @source_theme_css ||=
      Rouge::Themes::Base16.mode(:dark).render(scope: ".rouge-src") +
      "\n.rouge-src { background: transparent; }"
  end

  private

  # Rouge-highlighted HTML for each source line (1-based line n -> index n - 1).
  # The whole file is lexed so multi-line tokens (heredocs, block comments) are
  # classified correctly, then each token's value is split on newlines so the
  # per-line rendering keeps every line's spans intact. Returns [] if highlighting
  # fails, so callers degrade to plain text rather than error a step.
  def highlighted_lines(abs_path, source)
    lexer = source_lexer(abs_path, source)
    formatter = Rouge::Formatters::HTML.new
    lines = [+""]
    lexer.lex(source).each do |token, value|
      value.split("\n", -1).each_with_index do |segment, i|
        lines << +"" if i.positive?
        lines[-1] << formatter.format([[token, segment]]) unless segment.empty?
      end
    end
    lines
  rescue => e
    Rails.logger.debug { "[SourceHelper] highlight failed for #{abs_path}: #{e.class}: #{e.message}" }
    []
  end

  # Pick a lexer from the filename/content, tolerating an ambiguous guess and
  # falling back to plain text for anything unrecognised.
  def source_lexer(abs_path, source)
    (Rouge::Lexer.guess(filename: abs_path, source: source) || Rouge::Lexers::PlainText).new
  rescue Rouge::Guesser::Ambiguous => e
    e.alternatives.first.new
  rescue
    Rouge::Lexers::PlainText.new
  end
end
