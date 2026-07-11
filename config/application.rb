require_relative "boot"

# This app has no database. We load the individual Rails railties instead of
# "rails/all" so that Active Record (and the engines that depend on it —
# Active Storage, Action Text, Action Mailbox) are never required.
require "rails"

require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cairn
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Keep the Tailwind source out of the served asset path. It shares the logical
    # name "application.css" with app/assets/stylesheets/application.css, so if both
    # are on the load path Propshaft raises on the ambiguity. tailwindcss-rails
    # excludes it too, but only in development/test where the gem is loaded — this
    # makes production (and the eventual packaged gem, which ships the compiled CSS
    # and drops the compiler) exclude it regardless. Mirrors the gem's engine hook.
    initializer "cairn.exclude_tailwind_source", before: "propshaft.append_assets_path" do |app|
      if app.config.assets.excluded_paths # nil unless Propshaft is loaded
        app.config.assets.excluded_paths << Rails.root.join("app/assets/tailwind")
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
