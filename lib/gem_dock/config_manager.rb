# @author Saiqul Haq <saiqulhaq@gmail.com>

require "yaml"
require "fileutils"
require_relative "validators"

module GemDock
  class ConfigManager
    include Validators

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

    attr_reader :config

    def initialize
      @config = load_config
    end

    def get(key)
      @config[key.to_s]
    end

    def set(key, value)
      key_s = key.to_s
      validate_config_key!(key_s, value)
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

    def validate_config_key!(key, value)
      case key
      when "mode"
        validate_mode!(value)
      when "auto_provision", "auto_cleanup_idle"
        validate_boolean!(value, field: key)
      when "idle_timeout_hours"
        validate_idle_timeout!(value)
      when "default_ruby_version"
        validate_ruby_version!(value)
      when "log_level"
        validate_log_level!(value)
      else
        raise ValidationError.new(
          "Unknown configuration key: #{key}",
          field: key,
          value: value,
          suggestion: "Valid keys are: #{DEFAULT_CONFIG.keys.join(", ")}"
        )
      end
    end
  end
end