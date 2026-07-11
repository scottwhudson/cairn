require "test_helper"

# The REPL is re-rendered on every stop and resume; `stopped` is the single switch
# that decides whether its input is live. Resuming past the breakpoint disables it
# until the next stop.
class Debug::ReplComponentTest < ViewComponent::TestCase
  test "at a stop the input is live" do
    repl = render_inline Debug::ReplComponent.new(stopped: true)

    assert_empty repl.css("input[disabled]"), "the repl input is live at a stop"
    assert_includes repl.to_html, "runs in the selected frame"
  end

  test "once resumed the input is disabled" do
    repl = render_inline Debug::ReplComponent.new(stopped: false)

    assert repl.css("input[disabled]").any?, "the repl input is dead once resumed"
    assert_includes repl.to_html, "reactivates at the next breakpoint"
  end

  # The controller appends entries into this id, and the component is the one place
  # it's named.
  test "it renders the output log the evaluations controller appends to" do
    repl = render_inline Debug::ReplComponent.new(stopped: true)

    assert_equal "repl-output", Debug::ReplComponent::OUTPUT_ID
    assert repl.css("##{Debug::ReplComponent::OUTPUT_ID}").any?
  end

  test "the panel renders the id the broadcaster replaces" do
    repl = render_inline Debug::ReplComponent.new(stopped: true)

    assert_equal "repl-panel", Debug::ReplComponent::ID
    assert repl.css("##{Debug::ReplComponent::ID}").any?
  end
end
