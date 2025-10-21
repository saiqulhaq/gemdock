# @author Saiqul Haq <saiqulhaq@gmail.com>

require "yaml"
require "fileutils"
require "time"
require_relative "validators"

module GemDock
  class StateManager
    include Validators

    STATE_DIR = File.join(Dir.pwd, ".gemdock").freeze
    STATE_FILE = File.join(STATE_DIR, "state.yml").freeze
    STATE_VERSION = "1.0.0".freeze

    attr_reader :state

    def initialize
      @state = load_state
    end

    def container_state(ruby_version)
      @state["containers"][ruby_version] || default_container_state
    end

    def update_container(ruby_version, updates)
      # Validate updates before applying
      validate_container_updates!(ruby_version, updates)
      
      @state["containers"][ruby_version] ||= default_container_state
      
      # Check state transition if status is being updated
      if updates["status"]
        old_status = @state["containers"][ruby_version]["status"]
        validate_state_transition!(old_status, updates["status"]) if old_status != updates["status"]
      end
      
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
      raise ValidationError.new("State must be a Hash") unless state.is_a?(Hash)
      raise ValidationError.new("Missing version field") unless state["version"]
      raise ValidationError.new("Missing containers field") unless state["containers"].is_a?(Hash)

      # Validate current_ruby exists in containers if set
      validate_current_ruby_exists!(state["current_ruby"], state["containers"]) if state["current_ruby"]

      state["containers"].each do |version, container|
        validate_container_state!(version, container)
      end
    end

    def validate_container_state!(version, container)
      status = container["status"]
      container_id = container["container_id"]
      volume_name = container["volume_name"]
      last_used = container["last_used"]
      created_at = container["created_at"]

      # Use validators module
      validate_container_status!(status)
      validate_container_id!(container_id)
      validate_container_id_consistency!(status, container_id)
      
      # Validate volume name matches version
      validate_volume_name!(volume_name, version) if volume_name
      
      # Validate timestamps
      validate_timestamp!(last_used, field: "last_used") if last_used
      validate_timestamp!(created_at, field: "created_at") if created_at
    end

    def validate_container_updates!(ruby_version, updates)
      # Validate status if present
      validate_container_status!(updates["status"]) if updates["status"]
      
      # Validate container_id if present
      validate_container_id!(updates["container_id"]) if updates.key?("container_id")
      
      # Validate consistency between status and container_id
      if updates["status"] || updates.key?("container_id")
        status = updates["status"] || @state["containers"][ruby_version]&.dig("status") || "not_provisioned"
        container_id = updates.key?("container_id") ? updates["container_id"] : @state["containers"][ruby_version]&.dig("container_id")
        validate_container_id_consistency!(status, container_id)
      end
      
      # Validate volume name if present
      validate_volume_name!(updates["volume_name"], ruby_version) if updates["volume_name"]
      
      # Validate timestamps if present
      validate_timestamp!(updates["last_used"], field: "last_used") if updates["last_used"]
      validate_timestamp!(updates["created_at"], field: "created_at") if updates["created_at"]
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