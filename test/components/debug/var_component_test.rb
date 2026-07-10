require "test_helper"

class Debug::VarComponentTest < ViewComponent::TestCase
  include Rails.application.routes.url_helpers

  TOGGLE = "button[data-action='stepper#toggleLocal']".freeze

  # rdbg hands back a variablesReference for nearly every value, so a positive ref
  # isn't enough to know there's anything inside: expanding a scalar yields an
  # empty list, and the caret promises a drill-down that never arrives.
  test "a scalar with a ref offers no disclosure caret" do
    row = render_inline Debug::VarComponent.new(var: {name: "n", value: "1", type: "Integer", ref: 9})

    assert_empty row.css(TOGGLE)
    assert_empty row.css("#var-children-9")
  end

  test "a structured value offers a caret and the container its children fill" do
    row = render_inline Debug::VarComponent.new(var: {name: "u", value: "#<User>", type: "User", ref: 9})

    assert_equal debug_session_local_path(9), row.css(TOGGLE).attr("data-stepper-url-param").value
    assert_equal 1, row.css("#var-children-9").size
  end

  # stepper#toggleLocal is handed the container's id rather than rebuilding it in
  # JS, so the row and the container can't drift apart.
  test "the caret carries the id of the container it opens" do
    row = render_inline Debug::VarComponent.new(var: {name: "u", value: "#<User>", type: "User", ref: 9})

    assert_equal Debug::VarComponent.children_id(9),
      row.css(TOGGLE).attr("data-stepper-container-param").value
  end

  test "a ref of zero is never drillable" do
    row = render_inline Debug::VarComponent.new(var: {name: "u", value: "#<User>", type: "User", ref: 0})

    assert_empty row.css(TOGGLE)
  end

  # The controller that fills the container has to name it the same way the row does.
  test "the children container id is the one the locals controller targets" do
    assert_equal "var-children-42", Debug::VarComponent.children_id("42")
  end
end
