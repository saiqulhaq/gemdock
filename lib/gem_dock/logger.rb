# @author Saiqul Haq <saiqulhaq@gmail.com>

require "logger"
require "fileutils"
require "json"
require "time"

module GemDock
  class Logger
    LOG_DIR = File.join(Dir.pwd, ".gemdock", "logs").freeze
    LOG_FILE = File.join(LOG_DIR, "gemdock.log").freeze
    MAX_LOG_SIZE = 10 * 1024 * 1024 # 10 MB
    LOG_SHIFTS = 5 # Keep 5 old log files

    def initialize(level: ::Logger::INFO)
      FileUtils.mkdir_p(LOG_DIR)
      @logger = ::Logger.new(LOG_FILE, LOG_SHIFTS, MAX_LOG_SIZE)
      @logger.level = level
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        log_entry = {
          timestamp: datetime.utc.iso8601,
          level: severity.downcase
        }

        if msg.is_a?(Hash)
          log_entry[:message] = msg.delete(:message) || ""
          log_entry.merge!(msg)
        else
          log_entry[:message] = msg
        end

        "#{log_entry.to_json}\n"
      end
    end

    def info(message, **context)
      log(:info, message, context)
    end

    def warn(message, **context)
      log(:warn, message, context)
    end

    def error(message, **context)
      log(:error, message, context)
    end

    def debug(message, **context)
      log(:debug, message, context)
    end

    private

    def log(level, message, context)
      full_message = {message: message}.merge(context)
      @logger.send(level, full_message)
    end
  end
end