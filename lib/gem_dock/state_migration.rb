# frozen_string_literal: true

require_relative "logger"
require_relative "utils"

module GemDock
  class StateMigration
    class UnsupportedVersionError < StandardError; end

    CURRENT_VERSION = "1.0.0"
    SUPPORTED_VERSIONS = ["1.0.0"].freeze

    attr_reader :logger

    def initialize(logger: nil)
      @logger = logger || Logger.new(Utils.log_file_path)
    end

    # Detects the state file version
    # @param state [Hash] state data
    # @return [String, nil] version string or nil for legacy format
    def detect_version(state)
      return nil unless state.is_a?(Hash)
      state["version"]
    end

    # Checks if migration is needed
    # @param state [Hash] state data
    # @return [Boolean] true if migration needed
    def migration_needed?(state)
      version = detect_version(state)
      version.nil? || version != CURRENT_VERSION
    end

    # Migrates state to current version
    # @param state_file_path [String] path to state file
    # @return [Hash] migrated state data
    def migrate(state_file_path)
      unless File.exist?(state_file_path)
        logger.info("No state file to migrate", file: state_file_path)
        return default_state
      end

      state = load_state(state_file_path)
      version = detect_version(state)

      if version && !SUPPORTED_VERSIONS.include?(version)
        handle_unsupported_version(version)
      end

      if version.nil?
        logger.info("Detected legacy state format, migrating to v#{CURRENT_VERSION}")
        backup_state_file(state_file_path)
        migrate_legacy_to_v1(state)
      elsif version != CURRENT_VERSION
        logger.info("Migrating state from v#{version} to v#{CURRENT_VERSION}")
        backup_state_file(state_file_path)
        # Future migrations would go here
        state
      else
        logger.info("State file already at current version v#{CURRENT_VERSION}")
        state
      end
    end

    private

    # Loads state from file
    # @param state_file_path [String] path to state file
    # @return [Hash] state data
    def load_state(state_file_path)
      YAML.safe_load(File.read(state_file_path), permitted_classes: [Symbol, Time]) || {}
    rescue Psych::SyntaxError => e
      logger.error("Failed to parse state file", error: e.message, file: state_file_path)
      {}
    end

    # Backs up the original state file
    # @param state_file_path [String] path to state file
    def backup_state_file(state_file_path)
      backup_path = "#{state_file_path}.backup.#{Time.now.to_i}"
      FileUtils.cp(state_file_path, backup_path)
      logger.info("Backed up state file", original: state_file_path, backup: backup_path)
    rescue StandardError => e
      logger.warn("Failed to backup state file", error: e.message)
    end

    # Handles unsupported version error
    # @param version [String] unsupported version
    # @raise [UnsupportedVersionError]
    def handle_unsupported_version(version)
      message = "Unsupported state file version: #{version}. " \
                "Supported versions: #{SUPPORTED_VERSIONS.join(", ")}. " \
                "Please upgrade gemdock or restore from backup."
      
      logger.error(message)
      raise UnsupportedVersionError, message
    end

    # Migrates legacy format (pre-versioning) to v1.0.0
    # @param legacy_state [Hash] legacy state data
    # @return [Hash] migrated state in v1.0.0 format
    def migrate_legacy_to_v1(legacy_state)
      logger.info("Starting migration from legacy format to v1.0.0")

      migrated = {
        "version" => CURRENT_VERSION,
        "current_ruby" => legacy_state["current_ruby"],
        "containers" => migrate_containers(legacy_state["containers"] || {}),
        "last_updated" => Utils.format_timestamp
      }

      logger.info("Successfully migrated state to v1.0.0")
      migrated
    end

    # Migrates container data from legacy format
    # @param legacy_containers [Hash] legacy container data
    # @return [Hash] migrated container data
    def migrate_containers(legacy_containers)
      return {} unless legacy_containers.is_a?(Hash)

      migrated_containers = {}
      
      legacy_containers.each do |ruby_version, container_data|
        # Ensure container data has all required fields with defaults
        migrated_containers[ruby_version] = {
          "status" => container_data["status"] || "not_provisioned",
          "container_id" => container_data["container_id"],
          "volume_name" => container_data["volume_name"] || Utils.volume_name(ruby_version),
          "last_used" => container_data["last_used"] || Utils.format_timestamp,
          "last_updated" => container_data["last_updated"] || Utils.format_timestamp
        }

        logger.info("Migrated container data", ruby_version: ruby_version)
      end

      migrated_containers
    end

    # Returns default state structure for v1.0.0
    # @return [Hash] default state
    def default_state
      {
        "version" => CURRENT_VERSION,
        "current_ruby" => nil,
        "containers" => {},
        "last_updated" => Utils.format_timestamp
      }
    end
  end
end
