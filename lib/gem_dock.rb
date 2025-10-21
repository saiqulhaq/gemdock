require_relative "gem_dock/version"
require_relative "gem_dock/cli"
require_relative "gem_dock/config_manager"
require_relative "gem_dock/state_manager"
require_relative "gem_dock/container_cleanup"
require_relative "gem_dock/container_inspector"
require_relative "gem_dock/logger"

module GemDock
  class Error < StandardError; end

  DEFAULT_RUBY_VERSION = "3.2"
end
