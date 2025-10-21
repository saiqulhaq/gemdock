# @author Saiqul Haq <saiqulhaq@gmail.com>

require "time"

module GemDock
  module Validators
    # Container state validation
    VALID_CONTAINER_STATUSES = %w[running stopped not_provisioned].freeze
    CONTAINER_ID_PATTERN = /\A[a-f0-9]{64}\z/i.freeze
    
    # Configuration validation
    VALID_MODES = %w[persistent ephemeral].freeze
    VALID_LOG_LEVELS = %w[debug info warn error].freeze
    RUBY_VERSION_PATTERN = /\A\d+\.\d+\.\d+\z/.freeze
    
    # State transitions matrix
    VALID_STATE_TRANSITIONS = {
      "not_provisioned" => ["running"],
      "running" => ["stopped", "not_provisioned"],
      "stopped" => ["running", "not_provisioned"]
    }.freeze

    class ValidationError < StandardError
      attr_reader :field, :value, :suggestion

      def initialize(message, field: nil, value: nil, suggestion: nil)
        @field = field
        @value = value
        @suggestion = suggestion
        super(build_message(message, suggestion))
      end

      private

      def build_message(message, suggestion)
        return message unless suggestion
        "#{message}\nSuggestion: #{suggestion}"
      end
    end

    module_function

    # Container state validations
    def validate_container_status!(status, field: "status")
      unless VALID_CONTAINER_STATUSES.include?(status)
        raise ValidationError.new(
          "Invalid container status: '#{status}'",
          field: field,
          value: status,
          suggestion: "Valid statuses are: #{VALID_CONTAINER_STATUSES.join(", ")}"
        )
      end
    end

    def validate_container_id!(container_id, field: "container_id")
      return if container_id.nil?
      
      unless container_id.match?(CONTAINER_ID_PATTERN)
        raise ValidationError.new(
          "Invalid container_id format: '#{container_id}'",
          field: field,
          value: container_id,
          suggestion: "Container ID must be a 64-character hexadecimal string"
        )
      end
    end

    def validate_timestamp!(timestamp, field: "timestamp")
      Time.parse(timestamp.to_s)
    rescue ArgumentError => e
      raise ValidationError.new(
        "Invalid timestamp: '#{timestamp}'",
        field: field,
        value: timestamp,
        suggestion: "Timestamp must be in ISO 8601 format (e.g., 2025-10-19T14:30:00Z)"
      )
    end

    def validate_volume_name!(volume_name, ruby_version, field: "volume_name")
      return if volume_name.nil?
      
      expected = "bundler_data_ruby_#{sanitize_version(ruby_version)}"
      unless volume_name == expected
        raise ValidationError.new(
          "Volume name '#{volume_name}' doesn't match Ruby version '#{ruby_version}'",
          field: field,
          value: volume_name,
          suggestion: "Expected volume name: #{expected}"
        )
      end
    end

    def validate_state_transition!(from_status, to_status)
      valid_transitions = VALID_STATE_TRANSITIONS[from_status] || []
      
      unless valid_transitions.include?(to_status)
        raise ValidationError.new(
          "Invalid state transition from '#{from_status}' to '#{to_status}'",
          field: "status",
          value: to_status,
          suggestion: "Valid transitions from '#{from_status}': #{valid_transitions.join(", ")}"
        )
      end
    end

    # Configuration validations
    def validate_mode!(mode, field: "mode")
      unless VALID_MODES.include?(mode)
        raise ValidationError.new(
          "Invalid mode: '#{mode}'",
          field: field,
          value: mode,
          suggestion: "Valid modes are: #{VALID_MODES.join(", ")}"
        )
      end
    end

    def validate_boolean!(value, field:)
      unless [true, false].include?(value)
        raise ValidationError.new(
          "Invalid boolean value for #{field}: '#{value}'",
          field: field,
          value: value,
          suggestion: "Value must be true or false"
        )
      end
    end

    def validate_idle_timeout!(hours, field: "idle_timeout_hours")
      unless hours.is_a?(Integer) && hours.between?(1, 720)
        raise ValidationError.new(
          "Invalid idle timeout: #{hours}",
          field: field,
          value: hours,
          suggestion: "Idle timeout must be an integer between 1 and 720 hours (30 days)"
        )
      end
    end

    def validate_ruby_version!(version, field: "default_ruby_version")
      return if version.nil?
      
      unless version.match?(RUBY_VERSION_PATTERN)
        raise ValidationError.new(
          "Invalid Ruby version format: '#{version}'",
          field: field,
          value: version,
          suggestion: "Ruby version must be in X.Y.Z format (e.g., 3.2.0)"
        )
      end
    end

    def validate_log_level!(level, field: "log_level")
      unless VALID_LOG_LEVELS.include?(level)
        raise ValidationError.new(
          "Invalid log level: '#{level}'",
          field: field,
          value: level,
          suggestion: "Valid log levels are: #{VALID_LOG_LEVELS.join(", ")}"
        )
      end
    end

    # Cross-entity validations
    def validate_current_ruby_exists!(current_ruby, containers)
      return if current_ruby.nil?
      
      unless containers.key?(current_ruby)
        raise ValidationError.new(
          "Current Ruby version '#{current_ruby}' not found in containers",
          field: "current_ruby",
          value: current_ruby,
          suggestion: "Available versions: #{containers.keys.join(", ")}"
        )
      end
    end

    def validate_container_id_consistency!(status, container_id)
      if status == "not_provisioned" && !container_id.nil?
        raise ValidationError.new(
          "Container marked as 'not_provisioned' but has container_id: #{container_id}",
          field: "container_id",
          value: container_id,
          suggestion: "Remove container_id or change status to 'stopped' or 'running'"
        )
      end
      
      if status != "not_provisioned" && container_id.nil?
        raise ValidationError.new(
          "Container marked as '#{status}' but has no container_id",
          field: "container_id",
          value: nil,
          suggestion: "Provide a valid container_id or change status to 'not_provisioned'"
        )
      end
    end

    # Helper methods
    def sanitize_version(version)
      version.to_s.gsub(".", "_")
    end
  end
end
