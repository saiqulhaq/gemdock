# frozen_string_literal: true

require_relative "docker_command"
require_relative "container_health_check"
require_relative "state_manager"
require_relative "logger"
require_relative "utils"

module GemDock
  class ContainerLifecycle
    GRACEFUL_STOP_TIMEOUT = 30 # seconds

    attr_reader :docker, :health_check, :state_manager, :logger

    def initialize(docker: nil, health_check: nil, state_manager: nil, logger: nil)
      @docker = docker || DockerCommand.new
      @health_check = health_check || ContainerHealthCheck.new(docker: @docker)
      @state_manager = state_manager || StateManager.new
      @logger = logger || Logger.new
    end

    # Start a container using Docker Compose
    # @param ruby_version [String] Ruby version (e.g., "3.2.0")
    # @param compose_file [String] Path to docker-compose.yml
    # @return [Boolean] true if started successfully
    def start(ruby_version, compose_file:)
      container_name = Utils.container_name(ruby_version)
      
      logger.info("Starting container", ruby_version: ruby_version, container_name: container_name)

      # Check if already running
      current_state = state_manager.container_state(ruby_version)
      if current_state["status"] == "running"
        logger.info("Container already running", ruby_version: ruby_version)
        return true
      end

      # Start using docker compose
      result = docker.compose(
        "-f #{compose_file} up -d",
        timeout: DockerCommand::DOCKER_TIMEOUT
      )

      unless result[:success]
        logger.error("Failed to start container",
                    ruby_version: ruby_version,
                    error: result[:stderr])
        return false
      end

      # Get container ID
      container_id = get_container_id(container_name)
      
      unless container_id
        logger.error("Container started but ID not found", container_name: container_name)
        return false
      end

      # Verify container is healthy
      health_status = health_check.check(container_id, use_cache: false)
      
      unless health_status.healthy?
        logger.error("Container started but unhealthy",
                    ruby_version: ruby_version,
                    status: health_status.message)
        return false
      end

      # Update state
      state_manager.update_container(ruby_version, {
        "status" => "running",
        "container_id" => container_id,
        "last_used" => Utils.format_timestamp
      })

      logger.info("Container started successfully",
                 ruby_version: ruby_version,
                 container_id: container_id)
      
      true
    rescue StandardError => e
      logger.error("Failed to start container",
                  ruby_version: ruby_version,
                  error: e.message,
                  backtrace: e.backtrace.first(5))
      false
    end

    # Stop a container gracefully
    # @param ruby_version [String] Ruby version
    # @return [Boolean] true if stopped successfully
    def stop(ruby_version)
      container_name = Utils.container_name(ruby_version)
      
      logger.info("Stopping container", ruby_version: ruby_version, container_name: container_name)

      # Check current state
      current_state = state_manager.container_state(ruby_version)
      
      if current_state[:status] == "not_provisioned"
        logger.info("Container not provisioned", ruby_version: ruby_version)
        return true
      end

      if current_state[:status] == "stopped"
        logger.info("Container already stopped", ruby_version: ruby_version)
        return true
      end

      container_id = current_state[:container_id]

      # Stop container with graceful timeout
      result = docker.execute(
        "stop --time #{GRACEFUL_STOP_TIMEOUT} #{container_id}",
        timeout: GRACEFUL_STOP_TIMEOUT + 10
      )

      unless result[:success]
        logger.error("Failed to stop container",
                    ruby_version: ruby_version,
                    error: result[:stderr])
        return false
      end

      # Update state
      state_manager.update_container(ruby_version, {
        "status" => "stopped"
      })

      logger.info("Container stopped successfully", ruby_version: ruby_version)
      
      true
    rescue StandardError => e
      logger.error("Failed to stop container",
                  ruby_version: ruby_version,
                  error: e.message)
      false
    end

    # Restart a container
    # @param ruby_version [String] Ruby version
    # @param compose_file [String] Path to docker-compose.yml
    # @return [Boolean] true if restarted successfully
    def restart(ruby_version, compose_file:)
      logger.info("Restarting container", ruby_version: ruby_version)

      # Stop first
      return false unless stop(ruby_version)

      # Wait a moment for cleanup
      sleep 1

      # Start again
      return false unless start(ruby_version, compose_file: compose_file)

      # Verify health after restart
      current_state = state_manager.container_state(ruby_version)
      health_status = health_check.check(current_state[:container_id], use_cache: false)

      unless health_status.healthy?
        logger.error("Container restarted but unhealthy",
                    ruby_version: ruby_version,
                    status: health_status.message)
        return false
      end

      logger.info("Container restarted successfully", ruby_version: ruby_version)
      true
    rescue StandardError => e
      logger.error("Failed to restart container",
                  ruby_version: ruby_version,
                  error: e.message)
      false
    end

    # Remove a container and its associated volume
    # @param ruby_version [String] Ruby version
    # @param remove_volume [Boolean] Whether to remove the volume
    # @return [Boolean] true if removed successfully
    def remove(ruby_version, remove_volume: true)
      container_name = Utils.container_name(ruby_version)
      volume_name = Utils.volume_name(ruby_version)
      
      logger.info("Removing container",
                 ruby_version: ruby_version,
                 container_name: container_name,
                 remove_volume: remove_volume)

      current_state = state_manager.container_state(ruby_version)
      
      if current_state[:status] == "not_provisioned"
        logger.info("Container not provisioned, nothing to remove", ruby_version: ruby_version)
        return true
      end

      container_id = current_state[:container_id]

      # Stop container if running
      if current_state[:status] == "running"
        logger.info("Stopping container before removal", ruby_version: ruby_version)
        stop(ruby_version)
      end

      # Remove container
      result = docker.execute("rm -f #{container_id}", timeout: 30)
      
      unless result[:success]
        logger.error("Failed to remove container",
                    ruby_version: ruby_version,
                    error: result[:stderr])
        return false
      end

      # Remove volume if requested
      if remove_volume
        volume_result = docker.execute("volume rm #{volume_name}", timeout: 30)
        
        if volume_result[:success]
          logger.info("Volume removed", volume_name: volume_name)
        else
          logger.warn("Failed to remove volume",
                     volume_name: volume_name,
                     error: volume_result[:stderr])
        end
      end

      # Update state to not_provisioned
      state_manager.update_container(ruby_version, {
        "status" => "not_provisioned",
        "container_id" => nil
      })

      logger.info("Container removed successfully", ruby_version: ruby_version)
      
      true
    rescue StandardError => e
      logger.error("Failed to remove container",
                  ruby_version: ruby_version,
                  error: e.message)
      false
    end

    # Check if container is running
    # @param ruby_version [String] Ruby version
    # @return [Boolean] true if running
    def running?(ruby_version)
      state_manager.container_running?(ruby_version)
    end

    # Check if container is provisioned
    # @param ruby_version [String] Ruby version
    # @return [Boolean] true if provisioned
    def provisioned?(ruby_version)
      state_manager.container_provisioned?(ruby_version)
    end

    private

    # Get container ID by name
    def get_container_id(container_name)
      result = docker.execute(
        "ps -aq --filter name=^#{container_name}$",
        timeout: 5
      )

      return nil unless result[:success]

      container_id = result[:output].strip
      container_id.empty? ? nil : container_id
    end
  end
end
