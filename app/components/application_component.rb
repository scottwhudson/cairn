# Base for the regions of the page that repaint themselves.
#
# A stop arrives on the DapClient's dispatcher thread and has to repaint several
# regions at once; a controller repaints the same regions in response to a click.
# Both used to spell out the target's dom id and the partial that fills it, so
# every region's id lived in the template, the controller and the broadcaster with
# nothing checking that the three agreed.
#
# A component owns its id and renders it on its own root element, which settles the
# question that comment threads used to answer case by case: refreshing is always
# `replace`, never `update`. There is no page-owned wrapper left for an `update` to
# preserve, and no way to strip an id by replacing the element that carries it.
class ApplicationComponent < ViewComponent::Base
  # The dom id of this component's root element. Only components that are pushed
  # into the page need one.
  def id
    raise NotImplementedError, "#{self.class} must define #id and render it on its root element"
  end

  # Push this component's current rendering to every subscriber of `stream`.
  # `layout: false` because a broadcast renders outside a request and would
  # otherwise be wrapped in the application layout.
  def broadcast_replace_to(stream)
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: id, renderable: self, layout: false)
  end
end
