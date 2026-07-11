require "test_helper"

class Debug::ConfigTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("cairnrc")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write_rc(contents)
    path = File.join(@dir, ".cairnrc")
    File.write(path, contents)
    path
  end

  test "reads host, port, and repo_path from a YAML file" do
    config = Debug::Config.new(write_rc(<<~YAML))
      host: 10.0.0.5
      port: 9999
      repo_path: /Users/me/code/app
    YAML

    assert config.loaded?
    assert_equal "10.0.0.5", config.host
    assert_equal "9999", config.port
    assert_equal "/Users/me/code/app", config.repo_path
  end

  test "port comes back as a string even when written as a number" do
    assert_equal "12345", Debug::Config.new(write_rc("port: 12345\n")).port
  end

  test "strips a trailing slash from repo_path like attach does" do
    config = Debug::Config.new(write_rc("repo_path: /Users/me/code/app/\n"))
    assert_equal "/Users/me/code/app", config.repo_path
  end

  test "falls back to defaults with no file" do
    config = Debug::Config.new(nil)

    refute config.loaded?
    assert_equal Debug::Config::DEFAULT_HOST, config.host
    assert_nil config.port
    assert_nil config.repo_path
  end

  test "empty or partial files leave the rest at defaults" do
    config = Debug::Config.new(write_rc("port: 4000\n"))

    assert_equal Debug::Config::DEFAULT_HOST, config.host
    assert_equal "4000", config.port
    assert_nil config.repo_path
  end

  test "malformed YAML is swallowed and defaults are used" do
    config = Debug::Config.new(write_rc("host: [unterminated\n"))

    assert_equal Debug::Config::DEFAULT_HOST, config.host
    assert_nil config.port
  end

  test "a non-mapping file is ignored" do
    config = Debug::Config.new(write_rc("- just\n- a\n- list\n"))

    assert_equal Debug::Config::DEFAULT_HOST, config.host
  end

  test "locate honours $CAIRNRC before the built-in paths" do
    path = write_rc("host: 1.2.3.4\n")

    with_env("CAIRNRC", path) do
      assert_equal path, Debug::Config.locate
    end
  end

  test "locate ignores $CAIRNRC pointing at a missing file" do
    with_env("CAIRNRC", File.join(@dir, "nope")) do
      # Falls through to Rails.root / home, neither guaranteed here — just assert
      # it doesn't return the bogus override.
      refute_equal File.join(@dir, "nope"), Debug::Config.locate
    end
  end

  private

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end
end
