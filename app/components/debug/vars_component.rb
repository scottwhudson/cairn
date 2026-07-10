module Debug
  # A list of variable rows. Used both for a frame's top-level locals and, via
  # Debug::LocalsController, for the children streamed into a var's nested
  # container.
  class VarsComponent < ApplicationComponent
    def initialize(vars:)
      @vars = vars
    end

    private

    attr_reader :vars
  end
end
