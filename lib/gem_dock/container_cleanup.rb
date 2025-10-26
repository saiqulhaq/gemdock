# frozen_string_literal: true

require_relative "docker_command"
require_relative "state_manager"
require_relative "config_manager"
require_relative "container_lifecycle"
require_relative "utils"
require_relative "logger"
require_relative "prompt_helper"

module GemDock
  # Manages cleanup of unused containers and volumes
  class ContainerCleanup
    attr_reader :docker_command, :state_manager, :config_manager, :lifecycle, :logger

    def initialize(docker_command:, state_manager:, config_manager:, lifecycle:, logger: nil)
      @docker_command = docker_command
      @state_manager = state_manager
      @config_manager = config_manager
      @lifecycle = lifecycle
      @logger = logger || GemDock::Logger.new
    end

    # Clean up containers based on idle timeout
    # @param all [Boolean] Remove all stopped containers regardless of age
    # @param force [Boolean] Skip confirmation prompts
    # @param dry_run [Boolean] Show what would be cleaned without actually cleaning
    # @return [Hash] Cleanup results with counts
    def cleanup(all: false, force: false, dry_run: false)
      logger.info("Starting cleanup", all: all, force: force, dry_run: dry_run)

      candidates = identify_cleanup_candidates(all: all)

      if candidates.empty?
        logger.info("No containers to clean up")
        return { cleaned: 0, skipped: 0, failed: 0 }
      end

      if dry_run
        return dry_run_report(candidates)
      end

      unless force
        return { cleaned: 0, skipped: candidates.size, failed: 0 } unless confirm_cleanup(candidates)
      end

      perform_cleanup(candidates)
    end

    # Identify idle containers based on timeout
    # @param all [Boolean] Include all stopped containers
    # @return [Array<String>] List of Ruby versions to clean up
    def identify_cleanup_candidates(all: false)
      candidates = []
      timeout_hours = config_manager.get("idle_timeout") || 24

      state_manager.all_containers.each do |ruby_version, container_info|
        next if lifecycle.running?(ruby_version) # Never clean running containers

        if all
          candidates << ruby_version
        elsif idle_too_long?(container_info, timeout_hours)
          candidates << ruby_version
        end
      end

      logger.debug("Identified #{candidates.size} cleanup candidates", versions: candidates)
      candidates
    end

    # Remove a specific container and its resources
    # @param ruby_version [String] Ruby version to clean
    # @param remove_volume [Boolean] Also remove the volume
    # @return [Boolean] Success status
    def clean_container(ruby_version, remove_volume: true)
      logger.info("Cleaning container", ruby_version: ruby_version, remove_volume: remove_volume)

      # Remove container
      unless lifecycle.remove(ruby_version, remove_volume: remove_volume)
        logger.error("Failed to remove container", ruby_version: ruby_version)
        return false
      end

      # Remove compose file
      compose_file = compose_file_path(ruby_version)
      if File.exist?(compose_file)
        File.delete(compose_file)
        logger.debug("Removed compose file", path: compose_file)
      end

      # Update state
      state_manager.update_container(
        ruby_version,
        'status' => "not_provisioned",
        container_id: nil,
        volume_name: nil
      )

      logger.info("Successfully cleaned container", ruby_version: ruby_version)
      true
    rescue StandardError => e
      logger.error("Error cleaning container", ruby_version: ruby_version, error: e.message)
      false
    end

    # Get cleanup statistics
    # @return [Hash] Statistics about cleanable containers
    def cleanup_stats
      all_candidates = identify_cleanup_candidates(all: true)
      idle_candidates = identify_cleanup_candidates(all: false)

      {
        total_containers: state_manager.all_containers.size,
        running_containers: count_running_containers,
        stopped_containers: all_candidates.size,
        idle_containers: idle_candidates.size,
        idle_timeout_hours: config_manager.get("idle_timeout") || 24
      }
    end

    private

    def idle_too_long?(container_info, timeout_hours)
      return false unless container_info["last_used"]

      last_used = Time.parse(container_info["last_used"])
      idle_hours = (Time.now - last_used) / 3600

      idle_hours > timeout_hours
    rescue ArgumentError => e
      logger.warn("Invalid last_used timestamp", error: e.message)
      false
    end

    def confirm_cleanup(candidates)
      details = candidates.map do |version|
        container_info = state_manager.container_state(version)
        last_used = container_info["last_used"] || "unknown"
        volume = container_info["volume_name"] || "gemdock-ruby-#{Utils.sanitize_version(version)}"
        "- Ruby #{version}\n    Last used: #{last_used}\n    Volume: #{volume}"
      end

      question = "This will remove #{candidates.size} container(s) and their volumes. Continue?"
      PromptHelper.confirm_with_details(question, details: details, default: false)
    end

    def perform_cleanup(candidates)
      results = { cleaned: 0, skipped: 0, failed: 0 }

      candidates.each do |version|
        if clean_container(version, remove_volume: true)
          results[:cleaned] += 1
        else
          results[:failed] += 1
        end
      end

      logger.info("Cleanup completed", results: results)
      results
    end

    def dry_run_report(candidates)
      puts "\nDry run - would remove the following containers:"
      candidates.each do |version|
        container_info = state_manager.container_state(version)
        last_used = container_info["last_used"] || "unknown"
        volume_name = container_info["volume_name"]
        puts "  - Ruby #{version}"
        puts "    Last used: #{last_used}"
        puts "    Volume: #{volume_name}" if volume_name
      end

      { cleaned: 0, skipped: candidates.size, failed: 0, dry_run: true }
    end

    def count_running_containers
      state_manager.all_containers.count do |ruby_version, _|
        lifecycle.running?(ruby_version)
      end
    end

    def compose_file_path(ruby_version)
      sanitized = GemDock::Utils.sanitize_version(ruby_version)
      File.join(ENV["HOME"], ".gemdock", "docker-compose-ruby-#{sanitized}.yml")
    end
  end
end
