# frozen_string_literal: true

module GemDock
  module Utils
    class << self
      # Validates Ruby version format (X.Y.Z)
      # @param version [String] Ruby version string
      # @return [Boolean] true if valid format
      def valid_ruby_version?(version)
        return false unless version.is_a?(String)
        version.match?(/\A\d+\.\d+\.\d+\z/)
      end

      # Sanitizes Ruby version for use in Docker names (dots to underscores)
      # @param version [String] Ruby version (e.g., "3.2.0")
      # @return [String] sanitized version (e.g., "3_2_0")
      def sanitize_version(version)
        version.to_s.tr(".", "_")
      end

      # Generates Docker container name for a Ruby version
      # @param version [String] Ruby version (e.g., "3.2.0")
      # @return [String] container name (e.g., "gemdock-ruby-3-2-0")
      def container_name(version)
        "gemdock-ruby-#{sanitize_version(version)}"
      end

      # Generates Docker volume name for a Ruby version
      # @param version [String] Ruby version (e.g., "3.2.0")
      # @return [String] volume name (e.g., "bundler_data_ruby_3_2_0")
      def volume_name(version)
        "bundler_data_ruby_#{sanitize_version(version)}"
      end

      # Returns the .gemdock directory path
      # @param project_root [String, nil] project root path (defaults to current directory)
      # @return [String] absolute path to .gemdock directory
      def gemdock_dir(project_root = nil)
        root = project_root || Dir.pwd
        File.join(root, ".gemdock")
      end

      # Returns the state file path
      # @param project_root [String, nil] project root path (defaults to current directory)
      # @return [String] absolute path to state.yml
      def state_file_path(project_root = nil)
        File.join(gemdock_dir(project_root), "state.yml")
      end

      # Returns the config file path
      # @param project_root [String, nil] project root path (defaults to current directory)
      # @return [String] absolute path to config.yml
      def config_file_path(project_root = nil)
        File.join(gemdock_dir(project_root), "config.yml")
      end

      # Returns the log file path
      # @param project_root [String, nil] project root path (defaults to current directory)
      # @return [String] absolute path to gemdock.log
      def log_file_path(project_root = nil)
        File.join(gemdock_dir(project_root), "gemdock.log")
      end

      # Formats a timestamp in ISO 8601 format
      # @param time [Time, nil] time object (defaults to current time)
      # @return [String] ISO 8601 formatted timestamp
      def format_timestamp(time = nil)
        (time || Time.now.utc).iso8601
      end

      # Parses an ISO 8601 timestamp
      # @param timestamp [String] ISO 8601 formatted timestamp
      # @return [Time] parsed time object
      # @raise [ArgumentError] if timestamp is invalid
      def parse_timestamp(timestamp)
        Time.parse(timestamp)
      rescue ArgumentError => e
        raise ArgumentError, "Invalid timestamp format: #{timestamp}. Expected ISO 8601 format."
      end

      # Ensures the .gemdock directory exists
      # @param project_root [String, nil] project root path (defaults to current directory)
      # @return [String] path to created/existing directory
      def ensure_gemdock_dir(project_root = nil)
        dir = gemdock_dir(project_root)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        dir
      end

      # Checks if a container name is valid for gemdock
      # @param name [String] container name
      # @return [Boolean] true if valid gemdock container name
      def valid_container_name?(name)
        name.match?(/\Agemdock-ruby-\d+_\d+_\d+\z/)
      end

      # Extracts Ruby version from container name
      # @param name [String] container name (e.g., "gemdock-ruby-3-2-0")
      # @return [String, nil] Ruby version (e.g., "3.2.0") or nil if invalid
      def version_from_container_name(name)
        match = name.match(/\Agemdock-ruby-(\d+)_(\d+)_(\d+)\z/)
        return nil unless match
        "#{match[1]}.#{match[2]}.#{match[3]}"
      end

      # Extracts Ruby version from volume name
      # @param name [String] volume name (e.g., "bundler_data_ruby_3_2_0")
      # @return [String, nil] Ruby version (e.g., "3.2.0") or nil if invalid
      def version_from_volume_name(name)
        match = name.match(/\Abundler_data_ruby_(\d+)_(\d+)_(\d+)\z/)
        return nil unless match
        "#{match[1]}.#{match[2]}.#{match[3]}"
      end
    end
  end
end
