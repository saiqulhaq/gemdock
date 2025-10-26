# @author Saiqul Haq <saiqulhaq@gmail.com>

require_relative "docker_command"
require_relative "container_health_check"
require_relative "state_manager"
require_relative "utils"

module GemDock
  # Executes commands inside Docker containers
  #
  # This class handles command execution with:
  # - Pre-execution health checks
  # - Streaming or captured output
  # - Exit code propagation
  # - Working directory support
  # - Environment variable passing
  # - Interactive shell support
  #
  # @example Execute a command in a container
  #   executor = ContainerCommandExecutor.new
  #   result = executor.execute("3.2.0", "bundle install")
  #
  class ContainerCommandExecutor
    attr_reader :docker, :health_check, :state_manager, :logger

    # Initialize the command executor
    #
    # @param docker [DockerCommand] Docker command wrapper
    # @param health_check [ContainerHealthCheck] Health check service
    # @param state_manager [StateManager] State management service
    # @param logger [Logger] Logger instance
    def initialize(
      docker: DockerCommand.new,
      health_check: ContainerHealthCheck.new,
      state_manager: StateManager.new,
      logger: GemDock::Logger.instance
    )
      @docker = docker
      @health_check = health_check
      @state_manager = state_manager
      @logger = logger
    end

    # Execute a command in a container
    #
    # @param ruby_version [String] Ruby version
    # @param command [String] Command to execute
    # @param workdir [String, nil] Working directory inside container
    # @param env [Hash, nil] Environment variables to pass
    # @param stream_output [Boolean] Stream output in real-time
    # @param check_health [Boolean] Check container health before execution
    # @return [Hash] Execution result with :success, :output, :stderr, :exit_code
    def execute(
      ruby_version,
      command,
      workdir: nil,
      env: nil,
      stream_output: false,
      check_health: true
    )
      container_state = state_manager.container_state(ruby_version)

      unless container_state["status"] == "running"
        logger.error("Container not running", {
          ruby_version: ruby_version,
          status: container_state["status"]
        })
        return {
          success: false,
          output: "",
          stderr: "Container is not running (status: #{container_state["status"]})",
          exit_code: 1
        }
      end

      container_id = container_state["container_id"]

      if check_health && !verify_container_health(container_id, ruby_version)
        return {
          success: false,
          output: "",
          stderr: "Container health check failed",
          exit_code: 1
        }
      end

      logger.info("Executing command in container", {
        ruby_version: ruby_version,
        container_id: container_id,
        command: command
      })

      docker_command = build_docker_exec_command(container_id, command, workdir, env)

      result = docker.execute(docker_command, capture_output: !stream_output)

      if result[:success]
        logger.info("Command executed successfully", {
          ruby_version: ruby_version,
          exit_code: result[:exit_code]
        })
      else
        logger.warn("Command failed", {
          ruby_version: ruby_version,
          exit_code: result[:exit_code],
          stderr: result[:stderr]
        })
      end

      result
    end

    # Execute an interactive command (e.g., shell)
    #
    # @param ruby_version [String] Ruby version
    # @param command [String] Command to execute (default: "bash")
    # @param workdir [String, nil] Working directory inside container
    # @return [Integer] Exit code
    def execute_interactive(ruby_version, command: "bash", workdir: nil)
      container_state = state_manager.container_state(ruby_version)

      unless container_state["status"] == "running"
        logger.error("Container not running", {
          ruby_version: ruby_version,
          status: container_state["status"]
        })
        return 1
      end

      container_id = container_state["container_id"]

      logger.info("Starting interactive session", {
        ruby_version: ruby_version,
        container_id: container_id,
        command: command
      })

      docker_command = build_docker_exec_command(
        container_id,
        command,
        workdir,
        nil,
        interactive: true
      )

      # For interactive commands, we need to use system() to preserve TTY
      exit_code = system(docker_command) ? 0 : ($?.exitstatus || 1)

      logger.info("Interactive session ended", {
        ruby_version: ruby_version,
        exit_code: exit_code
      })

      exit_code
    end

    # Check if a container is ready to execute commands
    #
    # @param ruby_version [String] Ruby version
    # @return [Boolean] true if container is ready
    def ready?(ruby_version)
      container_state = state_manager.container_state(ruby_version)
      return false unless container_state["status"] == "running"

      container_id = container_state["container_id"]
      verify_container_health(container_id, ruby_version)
    end

    private

    # Verify container health before execution
    #
    # @param container_id [String] Container ID
    # @param ruby_version [String] Ruby version for logging
    # @return [Boolean] true if healthy
    def verify_container_health(container_id, ruby_version)
      status = health_check.check(container_id)

      if status.healthy?
        logger.debug("Container health check passed", {
          ruby_version: ruby_version,
          container_id: container_id
        })
        true
      else
        logger.error("Container health check failed", {
          ruby_version: ruby_version,
          container_id: container_id,
          status: status.status,
          message: status.message
        })
        false
      end
    end

    # Build docker exec command
    #
    # @param container_id [String] Container ID
    # @param command [String] Command to execute
    # @param workdir [String, nil] Working directory
    # @param env [Hash, nil] Environment variables
    # @param interactive [Boolean] Enable interactive mode
    # @return [String] Docker exec command
    def build_docker_exec_command(container_id, command, workdir, env, interactive: false)
      parts = ["exec"]

      if interactive
        parts << "-it"
      end

      if workdir
        parts << "-w" << workdir
      end

      if env
        env.each do |key, value|
          parts << "-e" << "#{key}=#{value}"
        end
      end

      parts << container_id

      # For interactive shells, don't wrap in sh -c
      if interactive
        parts << command
      else
        # Wrap command in shell for proper argument parsing
        parts << "sh" << "-c" << command
      end

      parts.join(" ")
    end
  end
end
