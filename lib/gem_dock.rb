require_relative "gem_dock/version"
require_relative "gem_dock/cli"

module GemDock
  class Error < StandardError; end

  DEFAULT_RUBY_VERSION = "3.2"
end
