ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Minitest 6 dropped `minitest/mock`, and the only thing these tests need from it
# is a way to stand in for the debug adapter (whose real methods talk to a socket)
# and for Turbo's broadcasts (which go out over ActionCable).
module MethodStubbing
  # Swap `target.name` for `impl` while the block runs, then put the original back.
  def stub_method(target, name, impl)
    original = target.method(name)
    target.define_singleton_method(name) { |*args, **kwargs, &blk| impl.call(*args, **kwargs, &blk) }
    yield
  ensure
    target.singleton_class.send(:remove_method, name)
    # Only redefine if removing ours didn't reveal an inherited definition.
    target.define_singleton_method(name, original) unless target.respond_to?(name)
  end
end

Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    include MethodStubbing

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Add more helper methods to be used by all tests here...
  end
end
