# @author Saiqul Haq <saiqulhaq@gmail.com>

require "yaml"
require "fileutils"

module GemDock
  class ConfigManager
    CONFIG_DIR = File.join(Dir.pwd, ".gemdock").freeze
    CONFIG_FILE = File.join(CONFIG_DIR, "config.yml").freeze

    DEFAULT_CONFIG = {
      "mode" => "persistent",
      "auto_provision" => true,
      "auto_cleanup_idle" => false,
      "idle_timeout_hours" => 24,
      "default_ruby_version" => nil,
      "log_level" => "info"
    }.freeze

    VALID_LOG_LEVELS = %w[debug info warn error].freeze
    VALID_MODES = %w[persistent ephemeral].freeze

    attr_reader :config

    def initialize
      @config = load_config
    end

    def get(key)
      @config[key.to_s]
    end

    def set(key, value)
      key_s = key.to_s
      validate!(key_s, value)
      @config[key_s] = value
      save_config
    end

    def persistent_mode?
      get("mode") == "persistent"
    end

    def ephemeral_mode?
      get("mode") == "ephemeral"
    end

    def auto_provision?
      get("auto_provision")
    end

    private

    def load_config
      ensure_config_file_exists
      user_config = YAML.safe_load(File.read(CONFIG_FILE)) || {}
      DEFAULT_CONFIG.merge(user_config)
    rescue Psych::SyntaxError
      # Handle corrupted YAML file
      DEFAULT_CONFIG.dup
    end

    def save_config
      temp_file = "#{CONFIG_FILE}.tmp.#{Process.pid}"
      File.write(temp_file, YAML.dump(@config))
      File.rename(temp_file, CONFIG_FILE)
    ensure
      File.delete(temp_file) if File.exist?(temp_file)
    end

    def ensure_config_file_exists
      return if File.exist?(CONFIG_FILE)

      FileUtils.mkdir_p(CONFIG_DIR)
      File.write(CONFIG_FILE, YAML.dump(DEFAULT_CONFIG))
    end

    def validate!(key, value)
      case key
      when "mode"
        raise ArgumentError, "Invalid mode: #{value}. Must be one of #{VALID_MODES.join(", ")}" unless VALID_MODES.include?(value)
      when "auto_provision", "auto_cleanup_idle"
        raise ArgumentError, "Invalid boolean value: #{value}" unless [true, false].include?(value)
      when "idle_timeout_hours"
        raise ArgumentError, "Idle timeout must be an integer between 1 and 720" unless value.is_a?(Integer) && value.between?(1, 720)
      when "default_ruby_version"
        raise ArgumentError, "Invalid Ruby version format: #{value}" unless value.nil? || value.match?(/\A\d+\.\d+\.\d+\z/)
      when "log_level"
        raise ArgumentError, "Invalid log level: #{value}. Must be one of #{VALID_LOG_LEVELS.join(", ")}" unless VALID_LOG_LEVELS.include?(value)
      else
        raise ArgumentError, "Unknown configuration key: #{key}"
      end
    end
  end
end