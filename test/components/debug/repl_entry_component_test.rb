require "test_helper"

# One console entry: the expression echoed back, then its result. A successful result
# is a var row that expands like a local; an error is shown flat and colored apart.
class Debug::ReplEntryComponentTest < ViewComponent::TestCase
  include Rails.application.routes.url_helpers

  def render_entry(expression:, result:)
    render_inline Debug::ReplEntryComponent.new(expression: expression, result: result)
  end

  test "the expression is echoed, highlighted when it can be" do
    entry = render_entry(expression: "1 + 1", result: {value: "2", type: "Integer", ref: 0})

    assert_includes entry.to_html, "1"
    assert entry.css("code.rouge-src").any?, "a lexable expression is highlighted"
  end

  test "a successful result renders as an expandable var row" do
    entry = render_entry(expression: "user", result: {value: "#<User>", type: "User", ref: 7})

    assert_includes entry.text, "#<User>"
    assert entry.css("#var-children-7").any?, "a structured result can be drilled into"
    assert_empty entry.css(".text-rose-300\\/90")
  end

  # An error isn't a value to drill into — it's a message, shown flat and rose.
  test "an error result is shown flat and colored apart" do
    entry = render_entry(expression: "boom", result: {error: true, value: "NameError: boom", ref: 0})

    assert_includes entry.to_html, "NameError: boom"
    assert_includes entry.to_html, "border-rose-700/60"
    assert_empty entry.css("button[data-action='stepper#toggleLocal']"), "an error offers no var caret"
  end

  # The result label is a fixed arrow, and the value/type/ref are threaded into the
  # var row unchanged.
  test "the result is labelled with an arrow carrying the value's ref" do
    entry = render_entry(expression: "user", result: {value: "#<User>", type: "User", ref: 7})

    assert_includes entry.to_html, "⇒"
    assert_equal debug_session_local_path(7),
      entry.css("button[data-action='stepper#toggleLocal']").attr("data-stepper-url-param").value
  end
end
