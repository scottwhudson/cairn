# A tiny ActiveRecord model backing the demo blog's root page.
# The tour's breakpoints land on `published` and `summary` so a reviewer can
# watch the real DB query build and each record get post-processed.
class Article < ActiveRecord::Base
  # Only articles that have been published, newest first. This scope is where
  # the root route's data actually comes from — step in to watch the relation
  # turn into SQL.
  scope :published, -> { where(published: true).order(published_at: :desc) }

  # A short, word-bounded teaser rendered on the index page. Called once per
  # article while the view iterates — a good spot to scrub forward/back through
  # loop iterations.
  def summary(limit = 80)
    text = body.to_s.strip
    return text if text.length <= limit

    truncated = text[0, limit]
    truncated = truncated[0, truncated.rindex(" ") || limit]
    "#{truncated}…"
  end

  def byline
    "#{author} · #{published_at.strftime('%b %-d, %Y')}"
  end
end
