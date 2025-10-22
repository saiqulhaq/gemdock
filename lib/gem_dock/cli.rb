# @author Saiqul Haq <saiqulhaq@gmail.com>

require "thor"
require "fileutils"
require "yaml"
require "shellwords"
require "net/http"
require "json"
require_relative "auto_provisioner"
require_relative "container_command_executor"
require_relative "container_lifecycle"
require_relative "container_provisioner"
require_relative "container_cleanup"
require_relative "container_inspector"
require_relative "state_manager"
require_relative "config_manager"
require_relative "validators"
require_relative "prompt_helper"

module GemDock
  # Config subcommand class - for configuration management
  class Config < Thor
    desc "list", "Show all configuration settings"
    def list
      config = config_manager.all
      
      puts "Current Configuration:"
      puts "=" * 50
      puts ""
      
      config.each do |key, value|
        display_value = value.nil? ? "(not set)" : value.to_s
        puts "  #{key}: #{display_value}"
      end
      
      puts ""
      puts "Configuration file: #{config_manager.config_file_path}"
    rescue StandardError => e
      puts "Error listing configuration: #{e.message}"
      exit 1
    end

    desc "get KEY", "Get a specific configuration value"
    def get(key)
      unless config_manager.key_exists?(key)
        puts "Error: Unknown configuration key '#{key}'"
        puts "Valid keys: #{config_manager.valid_keys.join(", ")}"
        exit 1
      end

      value = config_manager.get(key)
      display_value = value.nil? ? "(not set)" : value.to_s
      puts "#{key}: #{display_value}"
    rescue StandardError => e
      puts "Error getting configuration: #{e.message}"
      exit 1
    end

    desc "set KEY VALUE", "Set a configuration value"
    def set(key, value)
      unless config_manager.key_exists?(key)
        puts "Error: Unknown configuration key '#{key}'"
        puts "Valid keys: #{config_manager.valid_keys.join(", ")}"
        exit 1
      end
      
      # Convert string values to appropriate types
      converted_value = convert_value(key, value)
      
      config_manager.set(key, converted_value)
      puts "Configuration updated: #{key} = #{converted_value}"
      puts "Configuration saved to: #{config_manager.config_file_path}"
    rescue GemDock::Validators::ValidationError => e
      puts "Error: #{e.message}"
      exit 1
    rescue StandardError => e
      puts "Error setting configuration: #{e.message}"
      exit 1
    end

    desc "reset", "Reset configuration to defaults"
    method_option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation prompt"
    def reset
      unless options[:force]
        question = "This will reset all configuration to defaults. Continue?"
        unless PromptHelper.yes_no(question, default: false)
          puts "Reset cancelled."
          return
        end
      end

      config_manager.reset!
      puts "Configuration reset to defaults."
      puts "Configuration file: #{config_manager.config_file_path}"
    rescue StandardError => e
      puts "Error resetting configuration: #{e.message}"
      exit 1
    end

    private

    def config_manager
      @config_manager ||= GemDock::ConfigManager.new
    end

    def convert_value(key, value)
      case key
      when "auto_provision", "auto_cleanup_idle"
        # Convert to boolean
        case value.downcase
        when "true", "yes", "1"
          true
        when "false", "no", "0"
          false
        else
          raise GemDock::Validators::ValidationError.new(
            "Invalid boolean value: #{value}",
            field: key,
            value: value,
            suggestion: "Use: true, false, yes, no, 1, or 0"
          )
        end
      when "idle_timeout_hours"
        # Convert to integer
        Integer(value)
      else
        # Keep as string
        value
      end
    rescue ArgumentError
      raise GemDock::Validators::ValidationError.new(
        "Invalid integer value: #{value}",
        field: key,
        value: value,
        suggestion: "Provide a valid number"
      )
    end
  end

  # Provision subcommand class - defined first so it can be referenced
  class Provision < Thor
    desc "start [RUBY_VERSION]", "Start a container for the specified Ruby version"
    def start(ruby_version = nil)
      ruby_version ||= GemDock::DEFAULT_RUBY_VERSION
      project_path = Dir.pwd

      puts "Starting container for Ruby #{ruby_version}..."
      container_lifecycle.start(ruby_version, compose_file: compose_file_path(ruby_version))
      puts "Container started successfully!"
    rescue StandardError => e
      puts "Error: #{e.message}"
      exit 1
    end

    desc "stop [RUBY_VERSION]", "Stop a running container"
    def stop(ruby_version = nil)
      ruby_version ||= GemDock::DEFAULT_RUBY_VERSION

      puts "Stopping container for Ruby #{ruby_version}..."
      container_lifecycle.stop(ruby_version)
      puts "Container stopped successfully!"
    rescue StandardError => e
      puts "Error: #{e.message}"
      exit 1
    end

    desc "restart [RUBY_VERSION]", "Restart a container"
    def restart(ruby_version = nil)
      ruby_version ||= GemDock::DEFAULT_RUBY_VERSION

      puts "Restarting container for Ruby #{ruby_version}..."
      container_lifecycle.restart(ruby_version, compose_file: compose_file_path(ruby_version))
      puts "Container restarted successfully!"
    rescue StandardError => e
      puts "Error: #{e.message}"
      exit 1
    end

    desc "down [RUBY_VERSION]", "Remove a container and optionally its volume"
    method_option :remove_volume, type: :boolean, aliases: "-v", desc: "Also remove the associated volume"
    def down(ruby_version = nil)
      ruby_version ||= GemDock::DEFAULT_RUBY_VERSION

      if options[:remove_volume]
        puts "This will remove the container AND its volume (all gems and bundler data will be lost)."
        print "Are you sure? (yes/no): "
        response = $stdin.gets.chomp
        unless response.downcase == "yes"
          puts "Operation cancelled."
          return
        end
      end

      puts "Removing container for Ruby #{ruby_version}..."
      container_lifecycle.remove(ruby_version, remove_volume: options[:remove_volume] || false)
      puts "Container removed successfully!"
    rescue StandardError => e
      puts "Error: #{e.message}"
      exit 1
    end

    desc "create RUBY_VERSION", "Create and provision a new container"
    def create(ruby_version)
      project_path = Dir.pwd
      compose_dir = File.join(ENV["HOME"], ".gemdock")

      puts "Creating container for Ruby #{ruby_version}..."
      container_provisioner.provision(ruby_version, project_path: project_path, compose_dir: compose_dir)
      puts "Container provisioned successfully!"

      puts "Starting container..."
      container_lifecycle.start(ruby_version, compose_file: compose_file_path(ruby_version))
      puts "Container is ready to use!"
    rescue StandardError => e
      puts "Error: #{e.message}"
      exit 1
    end

    desc "list", "List all provisioned containers and their status"
    method_option :format, type: :string, aliases: "-f", desc: "Output format: text or json", default: "text"
    def list
      containers = state_manager.all_containers

      if containers.empty?
        if options[:format] == "json"
          puts "[]"
        else
          puts "No containers provisioned yet."
          puts "Run 'gemdock provision create VERSION' to create one."
        end
        return
      end

      if options[:format] == "json"
        # JSON output
        container_statuses = container_inspector.inspect_all_containers
        require "json"
        puts JSON.pretty_generate(container_statuses)
      else
        # Text output with icons and formatting
        puts "Provisioned containers:"
        puts ""
        
        container_statuses = container_inspector.inspect_all_containers
        container_statuses.each do |status|
          puts container_inspector.format_container_info(status)
          puts ""
        end
      end
    end

    private

    def container_lifecycle
      @container_lifecycle ||= GemDock::ContainerLifecycle.new(
        docker_command: docker_command,
        health_check: health_check,
        state_manager: state_manager
      )
    end

    def container_provisioner
      @container_provisioner ||= GemDock::ContainerProvisioner.new(
        docker_command: docker_command,
        state_manager: state_manager
      )
    end

    def health_check
      @health_check ||= GemDock::ContainerHealthCheck.new(
        docker_command: docker_command
      )
    end

    def docker_command
      @docker_command ||= GemDock::DockerCommand.new
    end

    def state_manager
      @state_manager ||= GemDock::StateManager.new
    end

    def container_inspector
      @container_inspector ||= GemDock::ContainerInspector.new(
        docker_command: docker_command,
        state_manager: state_manager,
        lifecycle: container_lifecycle,
        health_check: health_check
      )
    end

    def compose_file_path(ruby_version)
      sanitized = GemDock::Utils.sanitize_version(ruby_version)
      File.join(ENV["HOME"], ".gemdock", "docker-compose-ruby-#{sanitized}.yml")
    end
  end

  class CLI < Thor
    class << self
      # Hackery. Take the exec method away from Thor so that we can redefine it.
      # https://github.com/ddollar/foreman/issues/655#issuecomment-263188152
      def is_thor_reserved_word?(word, type)
        return false if word == "exec"
        super
      end

      def exit_on_failure?
        true
      end
    end

    desc "exec COMMAND [ARGS...]", "Execute arbitrary commands in the persistent container"
    method_option :ruby_version, type: :string, aliases: "-r", desc: "Ruby version to use (e.g., 3.2.0, 2.7.0)"
    method_option :workdir, type: :string, aliases: "-w", desc: "Working directory inside container"
    def exec(*args)
      if args.empty?
        puts "Error: No command specified"
        puts "Usage: gemdock exec [--ruby-version VERSION] [--workdir DIR] <command> [args...]"
        puts "Example: gemdock exec gem install bundler 2.4.22"
        puts "         gemdock exec --ruby-version 3.2.0 bundle gem myproject"
        puts "         gemdock exec shell  # Opens an interactive shell"
        exit 1
      end

      ruby_version = options[:ruby_version] || default_ruby_version
      project_path = Dir.pwd

      # Auto-provision container if needed
      auto_provisioner.ensure_ready(ruby_version, project_path: project_path)

      # Handle special 'shell' command
      if args.first == "shell"
        run_interactive_shell(ruby_version, options[:workdir])
      else
        run_command(ruby_version, args, options[:workdir])
      end
    rescue StandardError => e
      puts "Error: #{e.message}"
      exit 1
    end

    desc "provision SUBCOMMAND", "Manage container lifecycle"
    subcommand "provision", Provision

    desc "config SUBCOMMAND", "Manage configuration settings"
    subcommand "config", Config

    desc "switch VERSION", "Set the default Ruby version for future commands"
    def switch(ruby_version)
      # Validate Ruby version format
      unless GemDock::Utils.valid_ruby_version?(ruby_version)
        puts "Error: Invalid Ruby version format '#{ruby_version}'"
        puts "Expected format: X.Y.Z (e.g., 3.2.0)"
        exit 1
      end

      # Check if container is provisioned
      unless state_manager.container_provisioned?(ruby_version)
        puts "Error: Container for Ruby #{ruby_version} is not provisioned"
        puts "Run 'gemdock provision create #{ruby_version}' first"
        exit 1
      end

      # Update current Ruby version in state
      state_manager.set_current_ruby(ruby_version)

      # Update default Ruby version in config
      config_manager.set("default_ruby_version", ruby_version)

      puts "Switched default Ruby version to #{ruby_version}"
      
      # Show container status
      if container_lifecycle.running?(ruby_version)
        puts "Container is running and ready to use"
      else
        puts "Container is stopped. Run 'gemdock provision start #{ruby_version}' to start it"
      end
    rescue StandardError => e
      puts "Error switching version: #{e.message}"
      exit 1
    end

    desc "current", "Show the current default Ruby version"
    def current
      current_ruby = state_manager.state["current_ruby"]
      default_ruby = config_manager.get("default_ruby_version")

      if current_ruby
        puts "Current Ruby version: #{current_ruby}"
        if container_lifecycle.running?(current_ruby)
          puts "Status: running"
        else
          puts "Status: stopped"
        end
      elsif default_ruby
        puts "Default Ruby version: #{default_ruby} (not yet used)"
      else
        puts "No Ruby version set"
        puts "Run 'gemdock provision create VERSION' to create a container"
      end
    end

    desc "clean", "Remove unused containers and volumes"
    method_option :all, type: :boolean, aliases: "-a", desc: "Remove all stopped containers regardless of age"
    method_option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation prompts"
    method_option :dry_run, type: :boolean, aliases: "-d", desc: "Show what would be cleaned without actually cleaning"
    def clean
      # Show current stats
      stats = container_cleanup.cleanup_stats
      puts "Container Statistics:"
      puts "  Total containers: #{stats[:total_containers]}"
      puts "  Running: #{stats[:running_containers]}"
      puts "  Stopped: #{stats[:stopped_containers]}"
      puts "  Idle (>#{stats[:idle_timeout_hours]}h): #{stats[:idle_containers]}"
      puts ""

      # Perform cleanup
      results = container_cleanup.cleanup(
        all: options[:all] || false,
        force: options[:force] || false,
        dry_run: options[:dry_run] || false
      )

      # Show results
      if results[:dry_run]
        puts "\nDry run complete. Use 'gemdock clean --force' to actually remove containers."
      elsif results[:cleaned] > 0 || results[:failed] > 0
        puts "\nCleanup complete:"
        puts "  Cleaned: #{results[:cleaned]}"
        puts "  Failed: #{results[:failed]}" if results[:failed] > 0
      else
        puts "\nNo containers were cleaned."
      end
    rescue StandardError => e
      puts "Error during cleanup: #{e.message}"
      exit 1
    end

    desc "status", "Show current project and container status"
    def status
      project_status = container_inspector.project_status
      puts container_inspector.format_project_status(project_status)
    rescue StandardError => e
      puts "Error getting status: #{e.message}"
      exit 1
    end

    private

    def auto_provisioner
      @auto_provisioner ||= GemDock::AutoProvisioner.new(
        provisioner: container_provisioner,
        lifecycle: container_lifecycle,
        config_manager: config_manager,
        state_manager: state_manager
      )
    end

    def command_executor
      @command_executor ||= GemDock::ContainerCommandExecutor.new(
        health_check: health_check,
        docker_command: docker_command
      )
    end

    def container_lifecycle
      @container_lifecycle ||= GemDock::ContainerLifecycle.new(
        docker_command: docker_command,
        health_check: health_check,
        state_manager: state_manager
      )
    end

    def container_provisioner
      @container_provisioner ||= GemDock::ContainerProvisioner.new(
        docker_command: docker_command,
        state_manager: state_manager
      )
    end

    def health_check
      @health_check ||= GemDock::ContainerHealthCheck.new(
        docker_command: docker_command
      )
    end

    def docker_command
      @docker_command ||= GemDock::DockerCommand.new
    end

    def state_manager
      @state_manager ||= GemDock::StateManager.new
    end

    def config_manager
      @config_manager ||= GemDock::ConfigManager.new
    end

    def container_cleanup
      @container_cleanup ||= GemDock::ContainerCleanup.new(
        docker_command: docker_command,
        state_manager: state_manager,
        config_manager: config_manager,
        lifecycle: container_lifecycle
      )
    end

    def container_inspector
      @container_inspector ||= GemDock::ContainerInspector.new(
        docker_command: docker_command,
        state_manager: state_manager,
        lifecycle: container_lifecycle,
        health_check: health_check
      )
    end

    def run_interactive_shell(ruby_version, workdir = nil)
      puts "Opening interactive shell in Ruby #{ruby_version} container..."
      command_executor.execute_interactive(
        ruby_version,
        command: "/bin/bash",
        workdir: workdir
      )
    rescue StandardError => e
      puts "Error: #{e.message}"
      raise
    end

    def run_command(ruby_version, args, workdir = nil)
      command = args.join(" ")
      result = command_executor.execute(
        ruby_version,
        command,
        workdir: workdir,
        stream_output: true,
        check_health: true
      )
      exit result[:exit_code] if result[:exit_code] != 0
    rescue StandardError => e
      puts "Error: #{e.message}"
      raise
    end

    # pull the default ruby version from internet
    # return the last stable ruby version
    def default_ruby_version
      http_response = Net::HTTP.get_response(URI("https://api.github.com/repos/ruby/ruby/releases"))
      if http_response.code == "200"
        response = JSON.parse(http_response.body)
        response.first["name"]
      else
        GemDock::DEFAULT_RUBY_VERSION
      end
    rescue Timeout::Error => e
      puts "Timeout error: #{e.message}"
      GemDock::DEFAULT_RUBY_VERSION
    end
  end
end
