# The root route. Loads published articles from the database and hands them to
# the view. This is the method the tour opens on: set a breakpoint on the query
# line and step through the request end-to-end.
class ArticlesController < ApplicationController
  def index
    @articles = Article.published        # <- DB read for the root page
    @count = @articles.size              # forces the query to run here
    render :index
  end
end
