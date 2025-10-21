# @author Saiqul Haq <saiqulhaq@gmail.com>

require "yaml"
require "fileutils"
require "time"

module GemDock
  class StateManager
    STATE_DIR = File.join(Dir.pwd, ".gemdock").freeze
    STATE_FILE = File.join(STATE_DIR, "state.yml").freeze
    STATE_VERSION = "1.0.0".freeze

    VALID_STATUSES = %w[running stopped not_provisioned].freeze
    CONTAINER_ID_PATTERN = /\A[a-f0-9]{64}\z/i.freeze

    attr_reader :state

    def initialize
      @state = load_state
    end

    def container_state(ruby_version)
      @state["containers"][ruby_version] || default_container_state
    end

    def update_container(ruby_version, updates)
      @state["containers"][ruby_version] ||= default_container_state
      @state["containers"][ruby_version].merge!(updates)
      @state["last_updated"] = Time.now.utc.iso8601
      save_state
    end

    def current_ruby
      @state["current_ruby"]
    end

    def set_current_ruby(ruby_version)
      @state["current_ruby"] = ruby_version
      @state["last_updated"] = Time.now.utc.iso8601
      save_state
    end

    def container_running?(ruby_version)
      container_state(ruby_version)["status"] == "running"
    end

    def container_stopped?(ruby_version)
      container_state(ruby_version)["status"] == "stopped"
    end

    def container_provisioned?(ruby_version)
      container_state(ruby_version)["status"] != "not_provisioned"
    end

    def all_containers
      @state["containers"]
    end

    private

    def load_state
      ensure_state_file_exists
      
      raw_state = YAML.safe_load(File.read(STATE_FILE))
      validate_state!(raw_state)
      raw_state
    rescue Psych::SyntaxError => e
      handle_corrupted_state("YAML syntax error: #{e.message}")
    rescue => e
      handle_corrupted_state("Failed to load state: #{e.message}")
    end

    def save_state
      temp_file = "#{STATE_FILE}.tmp.#{Process.pid}"
      File.write(temp_file, YAML.dump(@state))
      File.rename(temp_file, STATE_FILE)
    ensure
      File.delete(temp_file) if File.exist?(temp_file)
    end

    def ensure_state_file_exists
      return if File.exist?(STATE_FILE)

      FileUtils.mkdir_p(STATE_DIR)
      File.write(STATE_FILE, YAML.dump(default_state))
    end

    def default_state
      {
        "version" => STATE_VERSION,
        "current_ruby" => nil,
        "project_root" => Dir.pwd,
        "last_updated" => Time.now.utc.iso8601,
        "containers" => {}
      }
    end

    def default_container_state
      {
        "container_id" => nil,
        "status" => "not_provisioned",
        "last_used" => Time.now.utc.iso8601,
        "volume_name" => nil,
        "compose_file" => nil,
        "created_at" => nil
      }
    end

    def validate_state!(state)
      raise "State must be a Hash" unless state.is_a?(Hash)
      raise "Missing version field" unless state["version"]
      raise "Missing containers field" unless state["containers"].is_a?(Hash)

      state["containers"].each do |version, container|
        validate_container_state!(version, container)
      end
    end

    def validate_container_state!(version, container)
      status = container["status"]
      container_id = container["container_id"]

      raise "Invalid status for #{version}: #{status}" unless VALID_STATUSES.include?(status)
      
      if status != "not_provisioned" && container_id
        raise "Invalid container_id format for #{version}" unless container_id.match?(CONTAINER_ID_PATTERN)
      end

      if status == "not_provisioned" && container_id
        raise "Container #{version} marked as not_provisioned but has container_id"
      end
    end

    def handle_corrupted_state(error_message)
      backup_corrupted_state if File.exist?(STATE_FILE)
      FileUtils.mkdir_p(STATE_DIR)
      File.write(STATE_FILE, YAML.dump(default_state))
      default_state
    end

    def backup_corrupted_state
      backup_file = "#{STATE_FILE}.backup.#{Time.now.to_i}"
      FileUtils.cp(STATE_FILE, backup_file)
    end
  end
end