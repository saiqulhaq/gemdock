# frozen_string_literal: true

module GemDock
  # Base error class for all GemDock errors
  class Error < StandardError
    attr_reader :suggestions, :details

    def initialize(message, suggestions: [], details: {})
      super(message)
      @suggestions = Array(suggestions)
      @details = details
    end

    # Format error message with suggestions
    def full_message
      msg = [message]
      
      unless suggestions.empty?
        msg << ""
        msg << "Suggestions:"
        suggestions.each { |s| msg << "  • #{s}" }
      end

      unless details.empty?
        msg << ""
        msg << "Details:"
        details.each { |k, v| msg << "  #{k}: #{v}" }
      end

      msg.join("\n")
    end
  end

  # Container-related errors
  class ContainerError < Error; end

  class ContainerNotFoundError < ContainerError
    def initialize(container_name, suggestions: [])
      default_suggestions = [
        "Run 'gemdock provision list' to see available containers",
        "Create a new container with 'gemdock provision create <version>'",
        "Check if the Ruby version format is correct (e.g., 3.2.0)"
      ]
      
      super(
        "Container '#{container_name}' not found",
        suggestions: suggestions.any? ? suggestions : default_suggestions
      )
    end
  end

  class ContainerNotRunningError < ContainerError
    def initialize(container_name, ruby_version = nil)
      suggestions = [
        "Start the container with 'gemdock provision start#{ruby_version ? " #{ruby_version}" : ""}'",
        "Check container status with 'gemdock provision list'",
        "Enable auto-provisioning with 'gemdock config set auto_provision true'"
      ]
      
      super(
        "Container '#{container_name}' is not running",
        suggestions: suggestions
      )
    end
  end

  class ContainerUnhealthyError < ContainerError
    def initialize(container_name, health_status)
      suggestions = [
        "Restart the container with 'gemdock provision restart'",
        "Check container logs for errors",
        "Remove and recreate the container with 'gemdock provision down' and 'gemdock provision create'"
      ]
      
      super(
        "Container '#{container_name}' is unhealthy (status: #{health_status})",
        suggestions: suggestions,
        details: { health_status: health_status }
      )
    end
  end

  # Docker-related errors
  class DockerError < Error; end

  class DockerNotAvailableError < DockerError
    def initialize
      suggestions = [
        "Install Docker Desktop from https://www.docker.com/products/docker-desktop",
        "Start Docker Desktop if it's already installed",
        "Ensure Docker daemon is running with 'docker ps'",
        "Check Docker installation with 'docker --version'"
      ]
      
      super(
        "Docker is not available or not running",
        suggestions: suggestions
      )
    end
  end

  class DockerCommandFailedError < DockerError
    def initialize(command, exit_code, output)
      suggestions = [
        "Check if Docker daemon is running",
        "Verify Docker permissions (you may need to add your user to docker group)",
        "Try running the command manually to see the full error: #{command}"
      ]
      
      super(
        "Docker command failed with exit code #{exit_code}",
        suggestions: suggestions,
        details: {
          command: command,
          exit_code: exit_code,
          output: output.to_s[0...200] # Limit output length (exclusive end)
        }
      )
    end
  end

  # Configuration errors
  class ConfigError < Error; end

  class InvalidConfigError < ConfigError
    def initialize(key, value, valid_values = nil)
      suggestions = []
      
      if valid_values && !valid_values.empty?
        suggestions << "Valid values for '#{key}': #{valid_values.join(', ')}"
      end
      
      suggestions += [
        "View all configuration with 'gemdock config list'",
        "Reset to defaults with 'gemdock config reset'",
        "See configuration documentation at https://github.com/saiqulhaq/gemdock#configuration"
      ]
      
      super(
        "Invalid configuration value '#{value}' for key '#{key}'",
        suggestions: suggestions,
        details: { key: key, value: value, valid_values: valid_values }
      )
    end
  end

  class ConfigKeyNotFoundError < ConfigError
    def initialize(key, available_keys)
      # Try to find similar keys for "did you mean?" suggestion
      similar = find_similar_keys(key, available_keys)
      
      suggestions = []
      suggestions << "Did you mean: #{similar.join(', ')}?" if similar.any?
      suggestions += [
        "View all configuration keys with 'gemdock config list'",
        "Valid keys are: #{available_keys.join(', ')}"
      ]
      
      super(
        "Unknown configuration key '#{key}'",
        suggestions: suggestions,
        details: { available_keys: available_keys }
      )
    end

    private

    def find_similar_keys(input, candidates)
      input_lower = input.downcase
      
      # Find keys with matching substring or similar length
      similar = candidates.select do |candidate|
        candidate_lower = candidate.downcase
        # Check for substring match or levenshtein distance
        distance = levenshtein_distance(input_lower, candidate_lower)
        candidate_lower.include?(input_lower) ||
          input_lower.include?(candidate_lower) ||
          distance <= 2
      end
      
      # Return up to 3 similar keys, but only if they're actually similar
      # Don't suggest keys that appear in "Valid keys are:" message
      similar.empty? ? [] : similar.first(3)
    end

    # Calculate Levenshtein distance between two strings
    def levenshtein_distance(str1, str2)
      return str2.length if str1.empty?
      return str1.length if str2.empty?

      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }

      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          matrix[i][j] = [
            matrix[i - 1][j] + 1,      # deletion
            matrix[i][j - 1] + 1,      # insertion
            matrix[i - 1][j - 1] + cost # substitution
          ].min
        end
      end

      matrix[str1.length][str2.length]
    end
  end

  # Version-related errors
  class VersionError < Error; end

  class InvalidRubyVersionError < VersionError
    def initialize(version)
      suggestions = [
        "Use format: X.Y.Z (e.g., 3.2.0, 2.7.8, 3.1.4)",
        "Check available Ruby versions at https://www.ruby-lang.org/en/downloads/releases/",
        "See provisioned versions with 'gemdock provision list'"
      ]
      
      super(
        "Invalid Ruby version format '#{version}'",
        suggestions: suggestions,
        details: { version: version }
      )
    end
  end

  class UnsupportedRubyVersionError < VersionError
    def initialize(version, min_version = "2.6.0")
      suggestions = [
        "Use Ruby version #{min_version} or higher",
        "Check supported versions at https://www.ruby-lang.org/en/downloads/",
        "Consider upgrading your project's Ruby version"
      ]
      
      super(
        "Ruby version '#{version}' is not supported (minimum: #{min_version})",
        suggestions: suggestions,
        details: { version: version, min_version: min_version }
      )
    end
  end

  # Command errors
  class CommandError < Error; end

  class MissingCommandError < CommandError
    def initialize(command_name = nil)
      suggestions = [
        "View all commands with 'gemdock help'",
        "Get help for a specific command with 'gemdock help <command>'",
        "Common commands: exec, provision, switch, status, config"
      ]
      
      message = command_name ? 
        "Command '#{command_name}' not found" :
        "No command specified"
      
      super(message, suggestions: suggestions)
    end
  end

  class MissingArgumentError < CommandError
    def initialize(command, argument)
      suggestions = [
        "View command usage with 'gemdock help #{command}'",
        "Example: gemdock #{command} <#{argument}>"
      ]
      
      super(
        "Missing required argument '#{argument}' for command '#{command}'",
        suggestions: suggestions,
        details: { command: command, argument: argument }
      )
    end
  end

  # File system errors
  class FileSystemError < Error; end

  class StateFileCorruptedError < FileSystemError
    def initialize(file_path, error_details = nil)
      suggestions = [
        "Backup the corrupted file: #{file_path}.bak",
        "Reset state with 'gemdock config reset'",
        "Manually delete the file and restart: rm #{file_path}",
        "Check file permissions and disk space"
      ]
      
      super(
        "State file is corrupted or unreadable: #{file_path}",
        suggestions: suggestions,
        details: { file_path: file_path, error: error_details }
      )
    end
  end

  class ConfigFileCorruptedError < FileSystemError
    def initialize(file_path, error_details = nil)
      suggestions = [
        "Check YAML syntax in: #{file_path}",
        "Reset configuration with 'gemdock config reset'",
        "View example configuration at https://github.com/saiqulhaq/gemdock#configuration",
        "Backup and recreate the file"
      ]
      
      super(
        "Configuration file is corrupted or invalid: #{file_path}",
        suggestions: suggestions,
        details: { file_path: file_path, error: error_details }
      )
    end
  end

  # Resource errors
  class ResourceError < Error; end

  class InsufficientResourcesError < ResourceError
    def initialize(resource_type, required, available)
      suggestions = [
        "Close unused applications to free up resources",
        "Increase Docker resource limits in Docker Desktop settings",
        "Remove unused containers with 'gemdock clean --all'",
        "Check system resources with 'docker system df'"
      ]
      
      super(
        "Insufficient #{resource_type}: required #{required}, available #{available}",
        suggestions: suggestions,
        details: {
          resource_type: resource_type,
          required: required,
          available: available
        }
      )
    end
  end
end
