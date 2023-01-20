require "active_support"
require "solid_cache"

module SolidCache
  class Engine < ::Rails::Engine
    isolate_namespace SolidCache

    config.solid_cache = ActiveSupport::OrderedOptions.new

    initializer "solid_cache" do |app|
      config.solid_cache.executor ||= app.executor

      config.after_initialize do
        SolidCache.executor = config.solid_cache.executor
        SolidCache.connects_to = config.solid_cache.connects_to
      end
    end
  end
end
