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
require_relative "state_manager"
require_relative "config_manager"

module GemDock
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
    def list
      containers = state_manager.all_containers

      if containers.empty?
        puts "No containers provisioned yet."
        puts "Run 'gemdock provision create VERSION' to create one."
        return
      end

      puts "Provisioned containers:"
      puts ""
      containers.each do |ruby_version, container_info|
        status = container_lifecycle.running?(ruby_version) ? "running" : "stopped"
        health = if container_lifecycle.running?(ruby_version)
          health_check.check(GemDock::Utils.container_name(ruby_version), use_cache: false)
          health_check.check(GemDock::Utils.container_name(ruby_version)).status
        else
          "n/a"
        end

        puts "  Ruby #{ruby_version}:"
        puts "    Status: #{status}"
        puts "    Health: #{health}" if status == "running"
        puts "    Container: #{container_info['container_id']}" if container_info['container_id']
        puts ""
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
