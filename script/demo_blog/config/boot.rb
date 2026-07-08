# Boots a real (if minimal) Rails 8 application in-process. `trace_entry.rb`
# requires this and then dispatches a GET "/" so the whole router -> controller
# -> ActiveRecord -> view stack runs under rdbg and can be traced.
#
# It reuses the tracer's own bundle (rails + pg), so there's no separate
# `bundle install`: rdbg inherits BUNDLE_GEMFILE from the process that spawns it.
require "action_controller/railtie"
require "active_record/railtie"

APP_ROOT = File.expand_path("..", __dir__)

class DemoBlog < Rails::Application
  config.load_defaults 8.1
  config.root = APP_ROOT
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "demo-blog-not-a-secret"
  config.hosts.clear                     # allow the in-process integration request
  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = :info

  routes.append do
    root to: "articles#index"
  end
end

DemoBlog.initialize!

# --- schema + seed (idempotent) ---------------------------------------------
# A real app would use migrations; for a self-contained demo we define the table
# inline and seed a few rows the first time the DB is empty.
def ensure_schema!
  conn = ActiveRecord::Base.connection
  return if conn.table_exists?(:articles)

  ActiveRecord::Schema.define do
    create_table :articles do |t|
      t.string   :title, null: false
      t.string   :author
      t.text     :body
      t.boolean  :published, null: false, default: false
      t.datetime :published_at
      t.timestamps
    end
  end
end

def seed!
  return if Article.count.positive?

  Article.create!([
    { title: "Tracing a request end to end",
      author: "Ada",  published: true,  published_at: 3.days.ago,
      body: "Reading a diff tells you what changed, but not what the code does. This post walks a request from the router down to the SQL and back up through the view." },
    { title: "Why the root route was slow",
      author: "Grace", published: true,  published_at: 1.day.ago,
      body: "A missing index turned a tiny query into a sequential scan over every article. Here is how we caught it by stepping through the controller." },
    { title: "Draft: things I have not finished yet",
      author: "Alan",  published: false, published_at: nil,
      body: "This one is still a draft, so the published scope should filter it out — a good thing to confirm while stepping through the query." },
  ])
end

ensure_schema!
seed!
