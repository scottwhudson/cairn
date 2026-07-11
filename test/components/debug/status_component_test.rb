require "test_helper"

# The status pill reports the session state and, once attached, offers break-on-raise
# and detach. Its logic is the state→color map (with a fallback), whether the controls
# appear at all (attached), and whether break-on-raise reads as armed.
class Debug::StatusComponentTest < ViewComponent::TestCase
  include Rails.application.routes.url_helpers

  Client = Struct.new(:break_on_exception)

  test "the state name is shown in the pill" do
    pill = render_inline Debug::StatusComponent.new(state: :running, client: Client.new(false))

    assert_includes pill.to_html, "running"
  end

  {running: "bg-emerald-500", stopped: "bg-amber-400", starting: "animate-pulse", terminated: "bg-zinc-500"}.each do |state, cls|
    test "#{state} colors the dot #{cls}" do
      pill = render_inline Debug::StatusComponent.new(state: state, client: Client.new(false))

      assert_includes pill.to_html, cls
    end
  end

  # An unknown state still gets a dot rather than an empty class attribute.
  test "an unrecognized state falls back to a neutral dot" do
    pill = render_inline Debug::StatusComponent.new(state: :whatever, client: Client.new(false))

    assert_includes pill.to_html, "bg-zinc-600"
  end

  # Detached: nothing to break-on or detach from, so neither control is offered.
  test "with no client the controls are hidden" do
    pill = render_inline Debug::StatusComponent.new(state: :terminated, client: nil)

    assert_not_includes pill.to_html, "break on raise"
    assert_not_includes pill.to_html, "Detach"
  end

  test "an attached session offers break-on-raise and detach" do
    pill = render_inline Debug::StatusComponent.new(state: :stopped, client: Client.new(false))

    assert_includes pill.to_html, "break on raise"
    assert_includes pill.to_html, "Detach"
  end

  # Armed vs not decides both the toggle's pressed state and whether the button posts
  # (arm) or deletes (disarm).
  test "an armed session presses the toggle and disarms on click" do
    pill = render_inline Debug::StatusComponent.new(state: :stopped, client: Client.new(true))

    assert_equal "true", pill.css("[aria-pressed]").first["aria-pressed"]
    assert pill.css("input[name='_method'][value='delete']").any?, "armed toggle should delete to disarm"
  end

  test "a disarmed session leaves the toggle unpressed and arms on click" do
    pill = render_inline Debug::StatusComponent.new(state: :stopped, client: Client.new(false))

    assert_equal "false", pill.css("[aria-pressed]").first["aria-pressed"]
    assert_empty pill.css("form[action='#{debug_session_exception_breakpoint_path}'] input[name='_method'][value='delete']")
  end

  test "the pill renders the id the broadcaster replaces" do
    pill = render_inline Debug::StatusComponent.new(state: :running, client: nil)

    assert_equal "session-status", Debug::StatusComponent::ID
    assert pill.css("##{Debug::StatusComponent::ID}").any?
  end
end
