require "test_helper"

# SourceHelper turns a file on disk into the source pane and colors the values the
# locals/REPL panes show. The interesting behavior is at the edges: files that don't
# exist, the trailing newline that isn't a line, and the inspect strings that can't
# go through the Ruby lexer.
class SourceHelperTest < ActionView::TestCase
  include SourceHelper

  def with_source(content)
    file = Tempfile.new(["src", ".rb"])
    file.write(content)
    file.close
    yield file.path
  ensure
    file.unlink
  end

  test "each line is numbered from one and carries its text" do
    with_source("a = 1\nb = 2\nc = 3") do |path|
      lines = source_lines(path, nil)

      assert_equal [1, 2, 3], lines.map(&:number)
      assert_equal ["a = 1", "b = 2", "c = 3"], lines.map(&:text)
    end
  end

  test "the focus line is the only one marked current" do
    with_source("a = 1\nb = 2\nc = 3") do |path|
      lines = source_lines(path, 2)

      assert_equal [false, true, false], lines.map(&:current)
    end
  end

  # split("\n", -1) leaves a trailing "" for a file that ends in a newline; that
  # phantom line would push the count past File.readlines and misalign the gutter.
  test "a trailing newline does not add a phantom final line" do
    with_source("a = 1\nb = 2\n") do |path|
      assert_equal 2, source_lines(path, nil).size
    end
  end

  # A lone blank file is one empty line, not zero — dropping the trailing "" only
  # applies when there's more than one line to begin with.
  test "an empty file is a single blank line" do
    with_source("") do |path|
      lines = source_lines(path, nil)

      assert_equal 1, lines.size
      assert_equal "", lines.first.text
    end
  end

  test "a missing file yields no lines rather than erroring" do
    assert_empty source_lines("/no/such/file.rb", 1)
  end

  test "a nil path yields no lines" do
    assert_empty source_lines(nil, 1)
  end

  test "the current line gets the highlight classes, others stay transparent" do
    current = SourceHelper::Line.new(number: 1, text: "x", html: nil, current: true)
    other = SourceHelper::Line.new(number: 2, text: "y", html: nil, current: false)

    assert_includes source_line_classes(current), "bg-sky-500/20"
    assert_includes source_line_classes(other), "border-transparent"
  end

  test "the theme css is scoped to the source class and blends its background" do
    css = source_theme_css

    assert_includes css, ".rouge-src"
    assert_includes css, "background: transparent"
  end

  test "the theme css is memoized to one string per process" do
    assert_same source_theme_css, source_theme_css
  end

  test "ruby is lexed into token spans" do
    assert_equal %(<span class="mi">1</span> <span class="o">+</span> <span class="mi">1</span>),
      highlight_ruby("1 + 1")
  end

  test "an empty expression is not highlighted" do
    assert_nil highlight_ruby("")
    assert_nil highlight_ruby(nil)
  end

  # inspect strings lead with `#<`, which the Ruby lexer reads as a comment; the
  # value scanner classifies the shapes inspect actually emits instead.
  test "an inspect string is scanned rather than lexed as a comment" do
    html = highlight_value("#<User:0x0000abcd @id=1>")

    assert_includes html, %(<span class="nc">User</span>)
    assert_includes html, %(<span class="vi">@id</span>)
  end

  # The 0x address is the reason a value can't be compared across stops, so it's
  # dimmed as a comment rather than shown as identifying detail.
  test "an object address is dimmed as a comment" do
    assert_includes highlight_value("#<User:0x0000abcd>"), %(<span class="c">:0x0000abcd</span>)
  end

  test "a bare string value keeps its string coloring" do
    assert_equal %(<span class="s2">"draft"</span>), highlight_value('"draft"')
  end

  test "an empty value is not highlighted" do
    assert_nil highlight_value("")
    assert_nil highlight_value(nil)
  end
end
