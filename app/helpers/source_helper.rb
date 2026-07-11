require "rouge"
require "strscan"

module SourceHelper
  Line = Struct.new(:number, :text, :html, :current)

  # Reads the whole source file and tags each line with whether it's the current
  # execution point. The file is lexed in full anyway (multi-line tokens demand
  # it), so rendering every line costs little beyond the markup; the pane scrolls
  # the current line into view. Each line also carries Rouge-highlighted HTML
  # (`html`); callers fall back to `text` when highlighting is unavailable.
  def source_lines(abs_path, focus_line)
    return [] unless abs_path && File.file?(abs_path)

    source = File.read(abs_path)
    # String#split returns [] for "", but an empty file is one blank line, not zero.
    text_lines = source.empty? ? [""] : source.split("\n", -1)
    # split's trailing "" from a final newline isn't a real line — drop it so the
    # line count matches File.readlines.
    text_lines.pop if text_lines.size > 1 && text_lines.last == ""
    html_lines = highlighted_lines(abs_path, source)

    text_lines.each_with_index.map do |text, i|
      Line.new(number: i + 1, text: text, html: html_lines[i], current: i + 1 == focus_line)
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

  # Rouge-highlighted HTML for a REPL expression — real Ruby the user typed, so the
  # Ruby lexer handles it. Returns nil when highlighting fails, so callers fall back
  # to the raw text rather than blanking the row. Callers supply the `.rouge-src`
  # scope the theme's CSS is written against.
  def highlight_ruby(text)
    text = text.to_s
    return nil if text.empty?

    format_tokens(Rouge::Lexers::Ruby.new.lex(text))
  rescue => e
    highlight_failed(text, e)
  end

  # Same, for the `inspect` string of a local or a REPL result. These can't go through
  # the Ruby lexer: `inspect` leads with `#<`, and `#` opens a comment in Ruby, so the
  # whole value lexes as one Comment token and renders flatter than the plain text it
  # replaced. Instead we scan for the handful of shapes `inspect` actually emits and
  # label them with the same Rouge tokens the source pane uses, so both panes are
  # colored by one theme.
  def highlight_value(text)
    text = text.to_s
    return nil if text.empty?

    format_tokens(scan_inspect(text))
  rescue => e
    highlight_failed(text, e)
  end

  private

  T = Rouge::Token::Tokens

  # Ordered: the first pattern to match at the scanner's cursor wins. The final
  # catch-all keeps the scanner advancing on input none of the others claim.
  #
  # `0x…` addresses are dimmed as comments — they're noise, and they're the reason a
  # value can't be compared across stops. The optional closing quote lets a string
  # that rdbg truncated mid-literal still lex as a string.
  INSPECT_TOKENS = [
    [/"(?:\\.|[^"\\])*"?/, T::Str::Double],       # "draft", or a cut-off "dra
    [/:0x\h+/, T::Comment],                       # :0x0000000126e47088
    [/@@?[A-Za-z_]\w*/, T::Name::Variable::Instance], # @user, @@count
    [/\b(?:nil|true|false)\b/, T::Keyword::Constant],
    [/[a-z_]\w*[?!]?(?=:(?!:))/, T::Str::Symbol], # id:  — a hash label, not a::b
    [/:[A-Za-z_]\w*[?!]?/, T::Str::Symbol],       # :draft
    [/-?\d[\d_]*\.\d+(?:[eE][+-]?\d+)?/, T::Num::Float],
    [/-?\d[\d_]*/, T::Num],
    [/[A-Z]\w*(?:::[A-Z]\w*)*/, T::Name::Class],  # Product, ActiveRecord::Base
    [/[#<>{}\[\](),=:]+/, T::Punctuation],
    [/\s+/, T::Text],
    [/./m, T::Text]
  ].freeze

  # [token, value] pairs for an inspect string, in the shape Rouge's formatter wants.
  def scan_inspect(text)
    scanner = StringScanner.new(text)
    tokens = []
    until scanner.eos?
      INSPECT_TOKENS.each do |pattern, token|
        next unless (value = scanner.scan(pattern))

        tokens << [token, value]
        break
      end
    end
    tokens
  end

  def format_tokens(tokens)
    Rouge::Formatters::HTML.new.format(tokens).html_safe
  end

  def highlight_failed(text, error)
    Rails.logger.debug { "[SourceHelper] highlight failed for #{text.truncate(60)}: #{error.class}: #{error.message}" }
    nil
  end

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
