# @author Saiqul Haq <saiqulhaq@gmail.com>

require "io/console"
require_relative "container_provisioner"
require_relative "container_lifecycle"
require_relative "state_manager"
require_relative "config_manager"
require_relative "prompt_helper"

module GemDock
  # Handles automatic provisioning of containers with user interaction
  #
  # This class manages the auto-provisioning workflow:
  # - Detects when containers need provisioning
  # - Prompts users for confirmation (when TTY available)
  # - Auto-starts stopped containers without prompting
  # - Supports CI/CD mode (no prompts, auto-provision enabled)
  # - Shows progress indicators for long operations
  #
  # @example Ensure container is ready
  #   auto_provisioner = AutoProvisioner.new
  #   auto_provisioner.ensure_ready("3.2.0")
  #
  class AutoProvisioner
    attr_reader :provisioner, :lifecycle, :state_manager, :config_manager, :logger

    # Initialize the auto-provisioner
    #
    # @param provisioner [ContainerProvisioner] Container provisioning service
    # @param lifecycle [ContainerLifecycle] Container lifecycle management
    # @param state_manager [StateManager] State management service
    # @param config_manager [ConfigManager] Configuration management
    # @param logger [Logger] Logger instance
    def initialize(
      provisioner: ContainerProvisioner.new,
      lifecycle: nil,
      state_manager: StateManager.new,
      config_manager: ConfigManager.new,
      logger: GemDock::Logger.instance
    )
      @provisioner = provisioner
      @lifecycle = lifecycle
      @state_manager = state_manager
      @config_manager = config_manager
      @logger = logger
    end

    # Ensure container is ready for use
    #
    # This method checks the container state and takes appropriate action:
    # - not_provisioned: Prompts to provision (or auto-provisions in CI/CD)
    # - stopped: Automatically starts without prompting
    # - running: Returns immediately
    #
    # @param ruby_version [String] Ruby version
    # @param project_path [String] Project directory path
    # @return [Boolean] true if container is ready, false otherwise
    def ensure_ready(ruby_version, project_path: Dir.pwd)
      container_state = state_manager.container_state(ruby_version)
      status = container_state["status"]

      logger.debug("Checking container readiness", {
        ruby_version: ruby_version,
        status: status
      })

      case status
      when "running"
        logger.debug("Container already running")
        true
      when "stopped"
        start_stopped_container(ruby_version, project_path)
      when "not_provisioned"
        provision_new_container(ruby_version, project_path)
      else
        logger.error("Unknown container status", status: status)
        false
      end
    end

    # Check if running in CI/CD environment
    #
    # @return [Boolean] true if in CI/CD mode
    def ci_mode?
      # Check common CI environment variables
      ENV["CI"] == "true" || 
        ENV["CONTINUOUS_INTEGRATION"] == "true" ||
        ENV["GITHUB_ACTIONS"] == "true" ||
        ENV["GITLAB_CI"] == "true" ||
        ENV["CIRCLECI"] == "true" ||
        ENV["JENKINS_HOME"] != nil ||
        ENV["BUILDKITE"] == "true"
    end

    # Check if TTY is available for interactive prompts
    #
    # @return [Boolean] true if TTY available and not in CI mode
    def tty_available?
      !ci_mode? && $stdin.tty? && $stdout.tty?
    end

    private

    # Start a stopped container
    #
    # @param ruby_version [String] Ruby version
    # @param project_path [String] Project path
    # @return [Boolean] true if started successfully
    def start_stopped_container(ruby_version, project_path)
      logger.info("Starting stopped container", ruby_version: ruby_version)
      
      compose_file = provisioner.compose_file_path(ruby_version, compose_dir: File.join(project_path, ".gemdock"))
      
      unless File.exist?(compose_file)
        logger.warn("Compose file not found, reprovisioning", compose_file: compose_file)
        return provision_new_container(ruby_version, project_path)
      end

      with_progress("Starting container") do
        lifecycle.start(ruby_version, compose_file: compose_file)
      end
    end

    # Provision a new container
    #
    # @param ruby_version [String] Ruby version
    # @param project_path [String] Project path
    # @return [Boolean] true if provisioned successfully
    def provision_new_container(ruby_version, project_path)
      # Check if auto-provisioning is enabled
      if !config_manager.auto_provision? && tty_available?
        return false unless prompt_for_provisioning(ruby_version)
      elsif !config_manager.auto_provision? && !tty_available?
        logger.error("Auto-provisioning is disabled and no TTY available", {
          ruby_version: ruby_version,
          suggestion: "Enable auto_provision in config or run interactively"
        })
        return false
      end

      logger.info("Provisioning new container", ruby_version: ruby_version)

      compose_file = with_progress("Generating Docker Compose configuration") do
        provisioner.provision(ruby_version, project_path: project_path)
      end

      success = with_progress("Starting container") do
        lifecycle.start(ruby_version, compose_file: compose_file)
      end

      if success
        logger.info("Container provisioned and started successfully", ruby_version: ruby_version)
      else
        logger.error("Failed to start provisioned container", ruby_version: ruby_version)
      end

      success
    end

    # Prompt user for provisioning confirmation
    #
    # @param ruby_version [String] Ruby version
    # @return [Boolean] true if user confirms
    def prompt_for_provisioning(ruby_version)
      question = "Container for Ruby #{ruby_version} is not provisioned. Would you like to provision it now?"
      
      result = PromptHelper.yes_no(question, default: false)
      
      unless result
        logger.info("User declined provisioning", ruby_version: ruby_version)
      end
      
      result
    end

    # Execute a block with progress indication
    #
    # Shows a simple progress indicator for operations that take time.
    # Only shows progress in TTY mode.
    #
    # @param message [String] Progress message
    # @yield Block to execute
    # @return Result of the block
    def with_progress(message)
      if tty_available?
        print "#{message}..."
        result = yield
        print " done.\n"
        result
      else
        logger.info(message)
        yield
      end
    end
  end
end
