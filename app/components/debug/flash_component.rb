module Debug
  # A transient error banner. The show page renders an empty element with this id
  # so there is always something for a broadcast to replace.
  class FlashComponent < ApplicationComponent
    ID = "session-flash".freeze

    def initialize(message:)
      @message = message
    end

    def id = ID

    private

    attr_reader :message
  end
end
