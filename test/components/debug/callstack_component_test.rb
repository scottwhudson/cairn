require "test_helper"

# The call-stack panel lists the frames of a stop and lets you pick one. The logic
# worth pinning is what it does without a snapshot, how it marks the selected frame,
# and when it offers the app/non-app filter (which needs a repo root to mean
# anything).
class Debug::CallstackComponentTest < ViewComponent::TestCase
  REPO = Rails.root.to_s

  def snapshot(frames)
    {reason: "breakpoint", frames: frames}
  end

  def app_frame(name: "call", line: 1)
    {id: 1, name: name, file: "#{REPO}/app/models/user.rb", line: line}
  end

  def gem_frame(name: "each", line: 2)
    {id: 2, name: name, file: "/gems/activerecord/lib/query.rb", line: line}
  end

  test "with no snapshot it says there is no active frame" do
    panel = render_inline Debug::CallstackComponent.new(snapshot: nil, repo_path: REPO)

    assert_includes panel.to_html, "No active frame"
  end

  test "each frame is listed with its name and repo-relative path" do
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot([app_frame(line: 12)]), repo_path: REPO)

    assert_includes panel.to_html, "call"
    assert_includes panel.to_html, "app/models/user.rb:12"
  end

  # The absolute repo prefix is stripped so the pane shows the path you'd recognize,
  # not the machine's checkout location.
  test "without a repo path the frame's absolute file is shown as-is" do
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot([gem_frame]), repo_path: nil)

    assert_includes panel.to_html, "/gems/activerecord/lib/query.rb:2"
  end

  test "the selected frame is flagged and the others are not" do
    frames = [app_frame(name: "outer"), app_frame(name: "inner")]
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot(frames), repo_path: REPO, frame_index: 1)

    selected = panel.css("li[data-selected='true']")
    assert_equal 1, selected.size
    assert_includes selected.to_html, "inner"
  end

  test "each frame carries its index for stepper#selectFrame" do
    frames = [app_frame, gem_frame]
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot(frames), repo_path: REPO)

    assert_equal %w[0 1], panel.css("button[data-action='stepper#selectFrame']").map { |b| b["data-stepper-frame-param"] }
  end

  # data-app is what the JS filter reads; app code under the repo is true, gem code
  # is false.
  test "app frames are tagged apart from gem frames" do
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot([app_frame, gem_frame]), repo_path: REPO)

    assert_equal %w[true false], panel.css("li[data-frame-filter-target='frame']").map { |li| li["data-app"] }
  end

  # No repo root means nothing can be classified as app code, so the filter would
  # only ever blank the pane — it isn't offered.
  test "the filter is offered only when a repo root can tell app from gem code" do
    with_repo = render_inline Debug::CallstackComponent.new(snapshot: snapshot([app_frame]), repo_path: REPO)
    without_repo = render_inline Debug::CallstackComponent.new(snapshot: snapshot([app_frame]), repo_path: nil)

    assert with_repo.css("button[data-mode='app']").any?
    assert_empty without_repo.css("button[data-mode='app']")
  end

  test "an empty stack offers no filter" do
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot([]), repo_path: REPO)

    assert_empty panel.css("button[data-mode='app']")
  end

  test "the panel renders the id the broadcaster replaces" do
    panel = render_inline Debug::CallstackComponent.new(snapshot: snapshot([app_frame]), repo_path: REPO)

    assert_equal "callstack-panel", Debug::CallstackComponent::ID
    assert panel.css("##{Debug::CallstackComponent::ID}").any?
  end
end
