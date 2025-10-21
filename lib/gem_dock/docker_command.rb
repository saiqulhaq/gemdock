# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "logger"

module GemDock
  class DockerCommand
    class CommandError < StandardError
      attr_reader :exit_code, :stderr, :command

      def initialize(message, exit_code: nil, stderr: nil, command: nil)
        super(message)
        @exit_code = exit_code
        @stderr = stderr
        @command = command
      end
    end

    class TimeoutError < CommandError; end

    DEFAULT_TIMEOUT = 30 # seconds
    DOCKER_TIMEOUT = 300 # 5 minutes for long-running operations like image pulls

    attr_reader :logger

    def initialize(logger: nil)
      @logger = logger || Logger.new
    end

    # Execute a Docker command with error handling and logging
    # @param command [String] Docker command to execute (without 'docker' prefix)
    # @param timeout [Integer] Command timeout in seconds
    # @param capture_output [Boolean] Whether to capture output or stream it
    # @return [Hash] Result hash with :success, :output, :exit_code, :stderr
    def execute(command, timeout: DEFAULT_TIMEOUT, capture_output: true)
      full_command = "docker #{command}"
      
      logger.info("Executing Docker command", command: full_command, timeout: timeout)
      start_time = Time.now

      begin
        result = if capture_output
                   execute_with_capture(full_command, timeout)
                 else
                   execute_with_stream(full_command, timeout)
                 end

        duration = Time.now - start_time
        logger.info("Docker command completed", 
                   command: full_command,
                   success: result[:success],
                   exit_code: result[:exit_code],
                   duration: duration.round(2))

        result
      rescue Timeout::Error
        duration = Time.now - start_time
        logger.error("Docker command timed out",
                    command: full_command,
                    timeout: timeout,
                    duration: duration.round(2))
        
        raise TimeoutError.new(
          "Docker command timed out after #{timeout} seconds",
          command: full_command
        )
      rescue StandardError => e
        duration = Time.now - start_time
        logger.error("Docker command failed",
                    command: full_command,
                    error: e.message,
                    duration: duration.round(2))
        raise
      end
    end

    # Execute docker compose commands
    # @param command [String] Docker compose command (without 'docker compose' prefix)
    # @param timeout [Integer] Command timeout in seconds
    # @return [Hash] Result hash
    def compose(command, timeout: DOCKER_TIMEOUT)
      execute("compose #{command}", timeout: timeout)
    end

    # Check if Docker daemon is available
    # @return [Boolean] true if Docker is available
    def docker_available?
      result = execute("info", timeout: 5)
      result[:success]
    rescue StandardError => e
      logger.warn("Docker not available", error: e.message)
      false
    end

    # Check if Docker Compose is available
    # @return [Boolean] true if Docker Compose is available
    def compose_available?
      result = execute("compose version", timeout: 5)
      result[:success]
    rescue StandardError => e
      logger.warn("Docker Compose not available", error: e.message)
      false
    end

    private

    # Execute command and capture all output
    def execute_with_capture(command, timeout)
      stdout_str, stderr_str, status = Timeout.timeout(timeout) do
        Open3.capture3(command)
      end

      {
        success: status.success?,
        output: stdout_str,
        stderr: stderr_str,
        exit_code: status.exitstatus
      }
    end

    # Execute command and stream output in real-time
    def execute_with_stream(command, timeout)
      stdout_lines = []
      stderr_lines = []
      exit_code = nil

      Timeout.timeout(timeout) do
        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          stdin.close

          # Read stdout and stderr in threads
          stdout_thread = Thread.new do
            stdout.each_line do |line|
              puts line
              stdout_lines << line
            end
          end

          stderr_thread = Thread.new do
            stderr.each_line do |line|
              $stderr.puts line
              stderr_lines << line
            end
          end

          # Wait for both threads to complete
          stdout_thread.join
          stderr_thread.join

          # Get exit status
          exit_code = wait_thr.value.exitstatus
        end
      end

      {
        success: exit_code.zero?,
        output: stdout_lines.join,
        stderr: stderr_lines.join,
        exit_code: exit_code
      }
    end
  end
end
