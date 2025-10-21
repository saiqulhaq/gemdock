# frozen_string_literal: true

require_relative "docker_command"
require_relative "state_manager"
require_relative "container_lifecycle"
require_relative "container_health_check"
require_relative "utils"
require_relative "logger"

module GemDock
  # Provides detailed container inspection and status reporting
  class ContainerInspector
    attr_reader :docker_command, :state_manager, :lifecycle, :health_check, :logger

    # Status icons for display
    ICONS = {
      running: "✅",
      stopped: "⏸️",
      not_provisioned: "❌",
      healthy: "💚",
      unhealthy: "💔",
      starting: "🔄"
    }.freeze

    def initialize(docker_command:, state_manager:, lifecycle:, health_check:, logger: nil)
      @docker_command = docker_command
      @state_manager = state_manager
      @lifecycle = lifecycle
      @health_check = health_check
      @logger = logger || GemDock::Logger.new
    end

    # Get detailed status for a specific Ruby version
    # @param ruby_version [String] Ruby version to inspect
    # @return [Hash] Detailed status information
    def inspect_container(ruby_version)
      container_state = state_manager.container_state(ruby_version)
      
      status = {
        ruby_version: ruby_version,
        provisioned: state_manager.container_provisioned?(ruby_version),
        running: lifecycle.running?(ruby_version),
        status_icon: status_icon(ruby_version),
        container_name: GemDock::Utils.container_name(ruby_version),
        container_id: container_state["container_id"],
        volume_name: container_state["volume_name"],
        last_used: container_state["last_used"],
        created_at: container_state["created_at"]
      }

      # Add health info if running
      if status[:running]
        health = health_check.check(status[:container_name], use_cache: false)
        status[:health_status] = health.status
        status[:health_message] = health.message
        status[:health_icon] = health_icon(health.status)
      end

      # Add resource usage if available
      if status[:running]
        status[:resources] = get_resource_usage(status[:container_name])
      end

      logger.debug("Inspected container", ruby_version: ruby_version, status: status[:running])
      status
    rescue StandardError => e
      logger.error("Error inspecting container", ruby_version: ruby_version, error: e.message)
      {
        ruby_version: ruby_version,
        provisioned: false,
        running: false,
        status_icon: ICONS[:not_provisioned],
        error: e.message
      }
    end

    # Get status for all containers
    # @return [Array<Hash>] Array of container statuses
    def inspect_all_containers
      containers = state_manager.all_containers
      
      containers.map do |ruby_version, _info|
        inspect_container(ruby_version)
      end.sort_by { |c| c[:ruby_version] }
    end

    # Get current project status
    # @return [Hash] Project status information
    def project_status
      current_ruby = state_manager.state["current_ruby"]
      
      {
        current_ruby_version: current_ruby,
        docker_available: docker_command.docker_available?,
        compose_available: docker_command.compose_available?,
        total_containers: state_manager.all_containers.size,
        running_containers: count_running_containers,
        current_container_status: current_ruby ? inspect_container(current_ruby) : nil
      }
    end

    # Format container info for display
    # @param status [Hash] Container status from inspect_container
    # @return [String] Formatted output
    def format_container_info(status)
      lines = []
      lines << "#{status[:status_icon]} Ruby #{status[:ruby_version]}"
      
      if status[:running]
        lines << "  Status: Running #{status[:health_icon]}"
        lines << "  Health: #{status[:health_status]}" if status[:health_status]
        lines << "  Container: #{status[:container_id]}" if status[:container_id]
        
        if status[:resources]
          lines << "  Memory: #{status[:resources][:memory]}" if status[:resources][:memory]
          lines << "  CPU: #{status[:resources][:cpu]}%" if status[:resources][:cpu]
        end
      elsif status[:provisioned]
        lines << "  Status: Stopped"
        lines << "  Container: #{status[:container_id]}" if status[:container_id]
      else
        lines << "  Status: Not Provisioned"
      end
      
      if status[:last_used]
        lines << "  Last used: #{format_timestamp(status[:last_used])}"
      end
      
      lines << "  Volume: #{status[:volume_name]}" if status[:volume_name]
      
      lines.join("\n")
    end

    # Format project status for display
    # @param status [Hash] Project status from project_status
    # @return [String] Formatted output
    def format_project_status(status)
      lines = []
      lines << "Project Status"
      lines << "=" * 50
      lines << ""
      
      if status[:current_ruby_version]
        lines << "Current Ruby: #{status[:current_ruby_version]}"
        if status[:current_container_status]
          container = status[:current_container_status]
          lines << "Container Status: #{container[:running] ? 'Running' : 'Stopped'} #{container[:status_icon]}"
          if container[:health_status]
            lines << "Health: #{container[:health_status]} #{container[:health_icon]}"
          end
        end
      else
        lines << "Current Ruby: Not set"
      end
      
      lines << ""
      lines << "Environment:"
      lines << "  Docker: #{status[:docker_available] ? '✅ Available' : '❌ Not available'}"
      lines << "  Docker Compose: #{status[:compose_available] ? '✅ Available' : '❌ Not available'}"
      lines << ""
      lines << "Containers:"
      lines << "  Total: #{status[:total_containers]}"
      lines << "  Running: #{status[:running_containers]}"
      
      lines.join("\n")
    end

    private

    def status_icon(ruby_version)
      return ICONS[:not_provisioned] unless state_manager.container_provisioned?(ruby_version)
      return ICONS[:running] if lifecycle.running?(ruby_version)
      ICONS[:stopped]
    end

    def health_icon(health_status)
      case health_status
      when :healthy
        ICONS[:healthy]
      when :unhealthy
        ICONS[:unhealthy]
      when :starting
        ICONS[:starting]
      else
        "❓"
      end
    end

    def get_resource_usage(container_name)
      # Get container stats
      command = "stats --no-stream --format \"{{.MemUsage}}|{{.CPUPerc}}\" #{container_name}"
      result = docker_command.execute(command, timeout: 5)
      
      return {} unless result[:exit_code].zero?
      
      parts = result[:stdout].strip.split("|")
      return {} if parts.size < 2
      
      {
        memory: parts[0].strip,
        cpu: parts[1]&.strip&.gsub("%", "")
      }
    rescue StandardError => e
      logger.warn("Failed to get resource usage", container: container_name, error: e.message)
      {}
    end

    def count_running_containers
      state_manager.all_containers.count do |ruby_version, _|
        lifecycle.running?(ruby_version)
      end
    end

    def format_timestamp(timestamp_str)
      return timestamp_str unless timestamp_str.is_a?(String)
      
      time = Time.parse(timestamp_str)
      now = Time.now
      diff = now - time
      
      case diff
      when 0..60
        "just now"
      when 61..3600
        "#{(diff / 60).to_i} minutes ago"
      when 3601..86400
        "#{(diff / 3600).to_i} hours ago"
      when 86401..2592000
        "#{(diff / 86400).to_i} days ago"
      else
        time.strftime("%Y-%m-%d %H:%M")
      end
    rescue ArgumentError
      timestamp_str
    end
  end
end
