require "test_helper"

# VarsComponent is the list wrapper shared by a frame's locals and a var's streamed
# children: one row per var, or an "(empty)" note when there are none.
class Debug::VarsComponentTest < ViewComponent::TestCase
  include Rails.application.routes.url_helpers

  def var(name)
    {name: name, value: "1", type: "Integer", ref: 0}
  end

  test "one row is rendered per var" do
    list = render_inline Debug::VarsComponent.new(vars: [var("a"), var("b"), var("c")])

    assert_includes list.to_html, "a"
    assert_includes list.to_html, "b"
    assert_includes list.to_html, "c"
  end

  # The empty case is a real state — an expanded container whose fetch came back with
  # no children — so it says "(empty)" rather than rendering nothing.
  test "an empty list says so" do
    list = render_inline Debug::VarsComponent.new(vars: [])

    assert_includes list.to_html, "(empty)"
  end

  test "a nil list is treated as empty" do
    list = render_inline Debug::VarsComponent.new(vars: nil)

    assert_includes list.to_html, "(empty)"
  end
end
