require "test_helper"

# Panels fixes the set of stop-scoped panels and their order; each panel is a
# component that knows the id it renders into. Rendering them is how we check the
# snapshot and frame index actually reached the component that was built with them.
class PanelsTest < ViewComponent::TestCase
  FakeClient = Struct.new(:repo_path)

  SOURCE = Rails.root.join("app/services/debug/session.rb").to_s

  def setup
    @client = FakeClient.new(Rails.root.to_s)
    @snapshot = {
      reason: "breakpoint", file: SOURCE, line: 10,
      frames: [
        {id: 1, name: "outer", file: SOURCE, line: 10,
         locals: [{name: "top_local", value: "1", type: "Integer", ref: 0}]},
        {id: 2, name: "inner", file: SOURCE, line: 20,
         locals: [{name: "deep_local", value: "2", type: "Integer", ref: 0}]}
      ],
      locals: []
    }
  end

  test "builds one component per panel, in render order" do
    panels = Debug::Panels.for(@client, @snapshot)

    assert_equal [Debug::SourceComponent, Debug::CallstackComponent, Debug::LocalsComponent],
      panels.map(&:class)
    assert_equal %w[source-panel callstack-panel locals-panel], panels.map(&:id)
  end

  test "every panel renders the snapshot it was built with" do
    source, callstack, locals = Debug::Panels.for(@client, @snapshot)

    assert_includes render_inline(source).to_html, "breakpoint"
    assert_includes render_inline(callstack).to_html, "outer"
    assert_includes render_inline(locals).to_html, ">top_local<"
  end

  test "the frame index selects which frame the panels focus on" do
    source, callstack, locals = Debug::Panels.for(@client, @snapshot, frame_index: 1)

    assert_includes render_inline(source).to_html, "app/services/debug/session.rb:20"
    assert_includes render_inline(callstack).css("li[data-selected='true']").text, "inner"
    assert_includes render_inline(locals).to_html, ">deep_local<"
  end

  test "defaults to the top frame" do
    source, = Debug::Panels.for(@client, @snapshot)

    assert_includes render_inline(source).to_html, "app/services/debug/session.rb:10"
  end

  # A nil snapshot is how the broadcaster blanks the panels on resume.
  test "a nil snapshot yields every panel in its empty state" do
    _source, callstack, locals = Debug::Panels.for(@client, nil)

    assert_includes render_inline(callstack).to_html, "No active frame"
    assert_includes render_inline(locals).to_html, "No locals in scope"
  end

  test "tolerates a detached session with no client" do
    source, = Debug::Panels.for(nil, nil)

    assert_includes render_inline(source).to_html, "Not attached"
  end
end
