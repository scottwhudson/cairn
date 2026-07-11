require "test_helper"

# The locals panel shows the variables of the selected frame. Its one bit of logic
# is where it reads them from: a frame's own locals, or — when there are no frames —
# the snapshot's top-level locals, or nothing.
class Debug::LocalsComponentTest < ViewComponent::TestCase
  def var(name)
    {name: name, value: "1", type: "Integer", ref: 0}
  end

  test "with no snapshot it says there are no locals" do
    panel = render_inline Debug::LocalsComponent.new(snapshot: nil)

    assert_includes panel.to_html, "No locals in scope"
  end

  test "the selected frame's locals are listed" do
    frames = [{id: 1, name: "f", locals: [var("shallow")]}, {id: 2, name: "g", locals: [var("deep")]}]
    panel = render_inline Debug::LocalsComponent.new(snapshot: {frames: frames}, frame_index: 1)

    assert_includes panel.to_html, "deep"
    assert_not_includes panel.to_html, "shallow"
  end

  # A snapshot with no frames still carries top-level locals; the panel falls back to
  # them so an early stop isn't blank.
  test "it falls back to the snapshot's own locals when there are no frames" do
    panel = render_inline Debug::LocalsComponent.new(snapshot: {frames: nil, locals: [var("bare")]})

    assert_includes panel.to_html, "bare"
  end

  test "a frame with no locals says so" do
    panel = render_inline Debug::LocalsComponent.new(snapshot: {frames: [{id: 1, name: "f", locals: []}]})

    assert_includes panel.to_html, "No locals in scope"
  end

  test "the panel renders the id the broadcaster replaces" do
    panel = render_inline Debug::LocalsComponent.new(snapshot: {frames: [{id: 1, name: "f", locals: [var("x")]}]})

    assert_equal "locals-panel", Debug::LocalsComponent::ID
    assert panel.css("##{Debug::LocalsComponent::ID}").any?
  end
end
