# @author Saiqul Haq <saiqulhaq@gmail.com>

require "semantic_logger"
require "fileutils"
require "json"
require "time"

module GemDock
  class Logger
    LOG_DIR = File.join(Dir.pwd, ".gemdock", "logs").freeze
    LOG_FILE = File.join(LOG_DIR, "gemdock.log").freeze

    def initialize(level: :info)
      FileUtils.mkdir_p(LOG_DIR)
      SemanticLogger.default_level = level
      @logger = ::SemanticLogger['GemDock']
      SemanticLogger.add_appender(file_name: LOG_FILE, formatter: :color)
    end

    def method_missing(method_name, *args, &block)
      if @logger.respond_to?(method_name)
        @logger.send(method_name, *args, &block)
      else
        super
      end
    end
  end
end