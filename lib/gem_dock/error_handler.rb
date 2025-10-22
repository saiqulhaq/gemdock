# frozen_string_literal: true

require_relative "errors"

module GemDock
  # Error handler module for formatting and displaying helpful error messages
  module ErrorHandler
    class << self
      # Handle and format errors with helpful suggestions
      # @param error [Exception] The error to handle
      # @param context [Hash] Additional context about where error occurred
      # @return [void] Prints formatted error and exits
      def handle(error, context = {})
        case error
        when GemDock::Error
          # Our custom errors with built-in suggestions
          print_custom_error(error)
        when GemDock::Validators::ValidationError
          # Validation errors from config/state
          print_validation_error(error, context)
        when DockerCommand::TimeoutError
          # Docker timeout errors (check before CommandError since it inherits from it)
          print_docker_timeout_error(error, context)
        when DockerCommand::CommandError
          # Docker command errors
          print_docker_error(error, context)
        when Errno::ENOENT
          # File not found
          print_file_not_found_error(error, context)
        when Errno::EACCES
          # Permission denied
          print_permission_error(error, context)
        when Psych::SyntaxError
          # YAML parsing error
          print_yaml_error(error, context)
        when JSON::ParserError
          # JSON parsing error
          print_json_error(error, context)
        when Thor::Error, Thor::UndefinedCommandError
          # Thor CLI errors
          print_thor_error(error, context)
        else
          # Generic errors
          print_generic_error(error, context)
        end

        exit 1
      end

      private

      def print_custom_error(error)
        puts PromptHelper.error(error.message)
        puts ""
        puts error.full_message
        puts ""
      end

      def print_validation_error(error, context)
        message = error.message
        
        # Enhanced suggestions based on error content
        suggestions = []
        
        if message.include?("Invalid value")
          suggestions << "Check the value format and try again"
          suggestions << "View valid options with 'gemdock config list'"
        end
        
        if message.include?("Ruby version")
          suggestions << "Use format: X.Y.Z (e.g., 3.2.0, 2.7.8)"
          suggestions << "See available versions with 'gemdock provision list'"
        end
        
        if context[:command]
          suggestions << "View help with 'gemdock help #{context[:command]}'"
        end
        
        puts PromptHelper.error("Validation Error")
        puts ""
        puts message
        
        unless suggestions.empty?
          puts ""
          puts "Suggestions:"
          suggestions.each { |s| puts "  • #{s}" }
        end
        
        puts ""
      end

      def print_docker_error(error, context)
        message = error.message
        
        # Check if Docker is running
        docker_running = system("docker info > /dev/null 2>&1")
        
        suggestions = []
        
        unless docker_running
          suggestions << "Docker is not running. Start Docker Desktop."
          suggestions << "Verify with: docker ps"
        else
          suggestions << "Check if the container exists: docker ps -a"
          suggestions << "View Docker logs for more details"
          suggestions << "Try restarting Docker Desktop"
        end
        
        if message.include?("permission denied")
          suggestions << "Add your user to docker group: sudo usermod -aG docker $USER"
          suggestions << "Or run with sudo (not recommended)"
        end
        
        puts PromptHelper.error("Docker Error")
        puts ""
        puts message
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
      end

      def print_docker_timeout_error(error, context)
        suggestions = [
          "Docker might be slow or unresponsive",
          "Check Docker resource settings (CPU/Memory)",
          "Try: docker system prune",
          "Restart Docker Desktop"
        ]
        
        puts PromptHelper.error("Docker Timeout Error")
        puts ""
        puts error.message
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
      end

      def print_file_not_found_error(error, context)
        # Try to extract file path from error message
        file_path_match = error.message.match(/No such file or directory @ rb_sysopen - (.+)/)
        file_path = file_path_match ? file_path_match[1] : error.message
        
        suggestions = []
        
        if file_path.include?(".gemdock") && file_path.include?("docker-compose")
          # Specific to docker-compose files
          suggestions << "Docker Compose file missing"
          suggestions << "Create container with: gemdock provision create VERSION"
        elsif file_path.include?(".gemdock")
          suggestions << "GemDock configuration directory not found"
          suggestions << "Run 'gemdock provision create VERSION' to initialize"
          suggestions << "Check permissions: ls -la ~/.gemdock"
        else
          suggestions << "File not found: #{file_path}"
          suggestions << "Check the file path and try again"
        end
        
        puts PromptHelper.error("File Not Found")
        puts ""
        puts "The file or directory could not be found: #{file_path}"
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
      end

      def print_permission_error(error, context)
        file_path = error.message.match(/Permission denied @ rb_sysopen - (.+)/)[1] rescue "unknown"
        
        suggestions = [
          "Check file permissions: ls -la #{File.dirname(file_path)}",
          "Ensure you have write access to: #{File.dirname(file_path)}",
          "Try running: chmod +w #{File.dirname(file_path)}"
        ]
        
        if file_path.include?(".gemdock")
          suggestions << "GemDock directory may have incorrect permissions"
          suggestions << "Fix with: chmod -R u+w ~/.gemdock"
        end
        
        puts PromptHelper.error("Permission Denied")
        puts ""
        puts "Cannot access file: #{file_path}"
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
      end

      def print_yaml_error(error, context)
        suggestions = [
          "Check YAML syntax in your configuration file",
          "Common issues: incorrect indentation, missing colons, unquoted special characters",
          "Reset configuration: gemdock config reset",
          "View example: https://github.com/saiqulhaq/gemdock#configuration"
        ]
        
        if context[:file]
          suggestions.unshift("Fix syntax errors in: #{context[:file]}")
        end
        
        puts PromptHelper.error("YAML Syntax Error")
        puts ""
        puts error.message
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
      end

      def print_json_error(error, context)
        suggestions = [
          "Invalid JSON format received",
          "This might be a temporary network issue",
          "Try the command again",
          "Check your internet connection"
        ]
        
        puts PromptHelper.error("JSON Parse Error")
        puts ""
        puts error.message
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
      end

      def print_thor_error(error, context)
        message = error.message
        
        suggestions = []
        
        if error.is_a?(Thor::UndefinedCommandError) || message.include?("Could not find command")
          # Extract the attempted command
          attempted = message.match(/"([^"]+)"/)[1] rescue nil
          
          suggestions << "View all commands with 'gemdock help'"
          suggestions << "Get help for a specific command with 'gemdock help <command>'"
          suggestions << "Common commands: exec, provision, switch, status, config"
          
          if attempted
            # Try to suggest similar commands
            similar = find_similar_commands(attempted)
            suggestions.unshift("Did you mean: #{similar.join(', ')}?") if similar.any?
          end
        elsif message.include?("required") || message.include?("missing")
          suggestions << "Check required arguments for this command"
          suggestions << "View command usage with 'gemdock help #{context[:command]}'" if context[:command]
        end
        
        puts PromptHelper.error("Command Error")
        puts ""
        puts message
        puts ""
        
        unless suggestions.empty?
          puts "Suggestions:"
          suggestions.each { |s| puts "  • #{s}" }
          puts ""
        end
      end

      def print_generic_error(error, context)
        suggestions = []
        
        if context[:command]
          suggestions << "View help for this command: gemdock help #{context[:command]}"
        end
        
        suggestions += [
          "Check 'gemdock status' to verify system state",
          "View logs for more details",
          "Report issues at: https://github.com/saiqulhaq/gemdock/issues"
        ]
        
        puts PromptHelper.error("Error")
        puts ""
        puts "#{error.class}: #{error.message}"
        puts ""
        puts "Suggestions:"
        suggestions.each { |s| puts "  • #{s}" }
        puts ""
        
        if ENV["DEBUG"] || ENV["GEMDOCK_DEBUG"]
          puts "Backtrace:"
          backtrace_lines = error.backtrace || []
          puts backtrace_lines.first(10).map { |line| "  #{line}" }
          puts ""
        else
          puts "Hint: Set GEMDOCK_DEBUG=1 for detailed error trace"
          puts ""
        end
      end

      def find_similar_commands(input)
        all_commands = [
          "exec", "provision", "config", "switch", "current", "clean", "status",
          "provision start", "provision stop", "provision restart", "provision down",
          "provision create", "provision list",
          "config list", "config get", "config set", "config reset"
        ]
        
        input_lower = input.downcase
        
        # Find commands with matching substring or small edit distance
        similar = all_commands.select do |cmd|
          cmd_lower = cmd.downcase
          cmd_lower.include?(input_lower) ||
            input_lower.include?(cmd_lower) ||
            levenshtein_distance(input_lower, cmd_lower) <= 2
        end
        
        similar.first(3)
      end

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
              matrix[i - 1][j] + 1,
              matrix[i][j - 1] + 1,
              matrix[i - 1][j - 1] + cost
            ].min
          end
        end

        matrix[str1.length][str2.length]
      end
    end
  end
end
