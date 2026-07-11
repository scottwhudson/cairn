require "test_helper"

# icon() is the single door to the SVG partials in app/views/shared/_icons. Its job
# is to fail loudly on a name typo rather than render a silent blank, and to pass the
# caller's Tailwind sizing through to the partial.
class IconsHelperTest < ActionView::TestCase
  include IconsHelper

  test "a known icon renders its svg partial" do
    assert_match(/<svg/, icon("play"))
  end

  test "the class param reaches the rendered svg" do
    assert_includes icon("play", class: "h-6 w-6 text-white"), "h-6 w-6 text-white"
  end

  test "a default class is applied when none is given" do
    assert_includes icon("play"), "h-4 w-4"
  end

  # A typo'd name would otherwise render nothing at all; raising names the mistake
  # and lists the icons that do exist.
  test "an unknown icon raises rather than rendering blank" do
    error = assert_raises(ArgumentError) { icon("nope") }

    assert_match(/unknown icon/, error.message)
    assert_match(/play/, error.message)
  end

  test "a symbol name is accepted" do
    assert_match(/<svg/, icon(:play))
  end

  # Every name the helper advertises must have a partial behind it, or the door
  # points at nothing.
  test "every advertised icon has a partial to render" do
    IconsHelper::ICONS.each do |name|
      assert_match(/<svg/, icon(name), "expected a partial for #{name}")
    end
  end
end
