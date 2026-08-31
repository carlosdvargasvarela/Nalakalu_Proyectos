require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FeatureProjectTypesDinamicos
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "America/Costa_Rica"
    # config.eager_load_paths << Rails.root.join("extras")

    config.i18n.default_locale = :es

    # PaperTrail serializes `versions.object_changes` as YAML. Changes to
    # timestamp attributes (e.g. `updated_at`) include `ActiveSupport::
    # TimeWithZone` values, which Psych's safe loader refuses to load unless
    # explicitly permitted — without this, `Version#changeset` silently
    # returns {} for every version instead of the real diff.
    config.active_record.yaml_column_permitted_classes = [
      Symbol, Date, Time, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone
    ]
  end
end
