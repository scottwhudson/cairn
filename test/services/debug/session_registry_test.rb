require "test_helper"

# SessionRegistry is the process-global parking spot for the one live DapClient:
# the job attaches a client and leaves it here so a later step request can look it
# back up. The state is a module singleton, so each test puts it back.
class Debug::SessionRegistryTest < ActiveSupport::TestCase
  def teardown
    Debug::SessionRegistry.clear
  end

  test "a parked client is handed back to a later lookup" do
    client = Object.new
    Debug::SessionRegistry.put(client)

    assert_same client, Debug::SessionRegistry.get
  end

  test "nothing is parked before a client is put" do
    assert_nil Debug::SessionRegistry.get
    assert_not Debug::SessionRegistry.active?
  end

  test "a parked client reads as active" do
    Debug::SessionRegistry.put(Object.new)

    assert Debug::SessionRegistry.active?
  end

  test "clearing detaches the parked client" do
    Debug::SessionRegistry.put(Object.new)
    Debug::SessionRegistry.clear

    assert_nil Debug::SessionRegistry.get
    assert_not Debug::SessionRegistry.active?
  end

  test "a second put replaces the first client" do
    first = Object.new
    second = Object.new
    Debug::SessionRegistry.put(first)
    Debug::SessionRegistry.put(second)

    assert_same second, Debug::SessionRegistry.get
  end

  # get/put/clear all take the lock, so concurrent attaches can't interleave into a
  # torn read — the last writer wins and every reader sees a whole client or nil.
  test "concurrent puts leave exactly one client parked" do
    clients = Array.new(20) { Object.new }
    threads = clients.map { |c| Thread.new { Debug::SessionRegistry.put(c) } }
    threads.each(&:join)

    assert_includes clients, Debug::SessionRegistry.get
  end
end
