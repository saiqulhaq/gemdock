# frozen_string_literal: true

require_relative "docker_command"
require_relative "logger"
require_relative "utils"

module GemDock
  class ContainerHealthCheck
    HEALTH_CHECK_TIMEOUT = 2 # seconds
    HEALTH_CHECK_CACHE_TTL = 5 # seconds

    HealthStatus = Struct.new(:status, :ruby_version, :message, :checked_at) do
      def healthy?
        status == :healthy
      end

      def unhealthy?
        status == :unhealthy
      end

      def not_found?
        status == :not_found
      end
    end

    attr_reader :docker_command, :logger, :health_cache

    def initialize(docker_command: nil, logger: nil)
      @docker_command = docker_command || DockerCommand.new
      @logger = logger || Logger.new
      @health_cache = {}
    end

    # Check container health
    # @param container_id [String] Docker container ID or name
    # @param use_cache [Boolean] Whether to use cached results
    # @return [HealthStatus] Health status object
    def check(container_id, use_cache: true)
      # Check cache first if enabled
      if use_cache && cached_result = get_cached_health(container_id)
        logger.debug("Using cached health check result", container_id: container_id)
        return cached_result
      end

      logger.info("Performing health check", container_id: container_id)
      status = perform_health_check(container_id)

      # Cache the result
      cache_health(container_id, status)

      status
    end

    # Check multiple containers
    # @param container_ids [Array<String>] Container IDs
    # @return [Hash] Map of container_id => HealthStatus
    def check_multiple(container_ids)
      container_ids.each_with_object({}) do |container_id, results|
        results[container_id] = check(container_id)
      end
    end

    # Clear health check cache
    # @param container_id [String, nil] Specific container or all if nil
    def clear_cache(container_id = nil)
      if container_id
        @health_cache.delete(container_id)
        logger.debug("Cleared health cache", container_id: container_id)
      else
        @health_cache.clear
        logger.debug("Cleared all health cache")
      end
    end

    private

    # Perform actual health check
    def perform_health_check(container_id)
      start_time = Time.now

      # First check if container exists and is running
      inspect_result = docker_command.execute(
        "inspect --format='{{.State.Status}}' #{container_id}",
        timeout: 2
      )

      unless inspect_result[:success]
        duration = Time.now - start_time
        logger.warn("Container not found",
                   container_id: container_id,
                   duration: duration.round(3))

        return HealthStatus.new(
          :not_found,
          nil,
          "Container not found",
          Time.now
        )
      end

      status = inspect_result[:output].strip

      unless status == "running"
        duration = Time.now - start_time
        logger.warn("Container not running",
                   container_id: container_id,
                   status: status,
                   duration: duration.round(3))

        return HealthStatus.new(
          :unhealthy,
          nil,
          "Container status: #{status}",
          Time.now
        )
      end

      # Check if container is responsive by executing Ruby version command
      exec_result = docker_command.execute(
        "exec #{container_id} ruby --version",
        timeout: HEALTH_CHECK_TIMEOUT
      )

      duration = Time.now - start_time

      if exec_result[:success]
        ruby_version = parse_ruby_version(exec_result[:output])

        logger.info("Container healthy",
                   container_id: container_id,
                   ruby_version: ruby_version,
                   duration: duration.round(3))

        HealthStatus.new(
          :healthy,
          ruby_version,
          "Container is responsive",
          Time.now
        )
      else
        logger.warn("Container unresponsive",
                   container_id: container_id,
                   error: exec_result[:stderr],
                   duration: duration.round(3))

        HealthStatus.new(
          :unhealthy,
          nil,
          "Container unresponsive: #{exec_result[:stderr]}",
          Time.now
        )
      end
    rescue DockerCommand::TimeoutError => e
      duration = Time.now - start_time
      logger.warn("Health check timed out",
                 container_id: container_id,
                 duration: duration.round(3))

      HealthStatus.new(
        :unhealthy,
        nil,
        "Health check timed out",
        Time.now
      )
    rescue StandardError => e
      duration = Time.now - start_time
      logger.error("Health check failed",
                  container_id: container_id,
                  error: e.message,
                  duration: duration.round(3))

      HealthStatus.new(
        :unhealthy,
        nil,
        "Health check error: #{e.message}",
        Time.now
      )
    end

    # Parse Ruby version from command output
    def parse_ruby_version(output)
      # Expected format: "ruby 3.2.0 (2022-12-25 revision a528908271) [arm64-darwin21]"
      match = output.match(/ruby (\d+\.\d+\.\d+)/)
      match ? match[1] : nil
    end

    # Get cached health status if available and not expired
    def get_cached_health(container_id)
      cached = @health_cache[container_id]
      return nil unless cached

      age = Time.now - cached.checked_at
      if age < HEALTH_CHECK_CACHE_TTL
        cached
      else
        @health_cache.delete(container_id)
        nil
      end
    end

    # Cache health status
    def cache_health(container_id, status)
      @health_cache[container_id] = status
    end
  end
end
