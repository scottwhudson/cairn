module Debug
  # The children of a structured local (hash/array/object), streamed into the
  # row's nested container. A plain read: the id is a variablesReference, a handle
  # into the current stop, and a stale one has nothing to show.
  class LocalsController < ApplicationController
    def show
      children = Session.expand(params[:id])
      return head(:no_content) unless children

      # `update`, not `replace`: the container is a shell VarComponent renders and
      # stepper_controller.js toggles. Only its contents are ours to fill.
      render turbo_stream: turbo_stream.update(
        VarComponent.children_id(params[:id]), VarsComponent.new(vars: children)
      )
    end
  end
end
