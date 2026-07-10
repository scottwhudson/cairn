module Debug
  # rdbg's catch breakpoint: stop the debuggee at a raise instead of letting it
  # unwind to its own error page. Arming it is a create, disarming a destroy — the
  # verb carries the state, so there's no boolean to cast.
  class ExceptionBreakpointsController < ApplicationController
    def create = arm(true)

    def destroy = arm(false)

    private

    # Re-renders the status region so the toggle reflects what the adapter
    # actually accepted, not what was clicked.
    def arm(enabled)
      client = Session.current
      return head(:unprocessable_entity) unless client

      Session.break_on_exception(enabled)
      replace(StatusComponent.new(state: client.state, client: client))
    rescue DapClient::Error => e
      replace(FlashComponent.new(message: "Could not arm exception breakpoint: #{e.message}"))
    end

    # Each component renders its own id-bearing root, so swapping it is a replace.
    def replace(component)
      render turbo_stream: turbo_stream.replace(component.id, component)
    end
  end
end
