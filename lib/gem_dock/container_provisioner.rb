# @author Saiqul Haq <saiqulhaq@gmail.com>

require "yaml"
require "fileutils"
require_relative "utils"
require_relative "validators"

module GemDock
  # Generates and manages Docker Compose configurations for Ruby containers
  #
  # This class handles the provisioning of Ruby containers by:
  # - Generating docker-compose.yml files for specific Ruby versions
  # - Managing volume mounts for the project directory
  # - Creating named volumes for bundler data
  # - Configuring container networking and naming
  #
  # @example Provision a Ruby 3.2.0 container
  #   provisioner = ContainerProvisioner.new(logger: logger)
  #   compose_file = provisioner.provision("3.2.0", project_path: "/app/myproject")
  #
  class ContainerProvisioner
    include Validators

    attr_reader :logger

    # Initialize the provisioner
    #
    # @param logger [Logger] Logger instance for operation tracking
    def initialize(logger: GemDock::Logger.instance)
      @logger = logger
    end

    # Provision a container for the specified Ruby version
    #
    # Generates a docker-compose.yml file with proper configuration for:
    # - Ruby version-specific container
    # - Volume mounts for project code
    # - Named volume for bundler data
    # - Network configuration
    #
    # @param ruby_version [String] Ruby version (e.g., "3.2.0")
    # @param project_path [String] Absolute path to the project directory
    # @param compose_dir [String] Directory where docker-compose.yml will be created
    # @return [String] Path to the generated docker-compose.yml file
    # @raise [ArgumentError] if ruby_version is invalid or project_path doesn't exist
    def provision(ruby_version, project_path: Dir.pwd, compose_dir: nil)
      validate_ruby_version!(ruby_version)
      validate_project_path!(project_path)

      compose_dir ||= File.join(project_path, ".gemdock")
      FileUtils.mkdir_p(compose_dir)

      compose_file = File.join(compose_dir, compose_filename(ruby_version))

      logger.info("Provisioning container", {
        ruby_version: ruby_version,
        project_path: project_path,
        compose_file: compose_file
      })

      compose_config = generate_compose_config(ruby_version, project_path)
      write_compose_file(compose_file, compose_config)

      logger.info("Container provisioned successfully", {
        ruby_version: ruby_version,
        compose_file: compose_file
      })

      compose_file
    end

    # Check if a compose file exists for the given Ruby version
    #
    # @param ruby_version [String] Ruby version
    # @param compose_dir [String] Directory to check for compose file
    # @return [Boolean] true if compose file exists
    def provisioned?(ruby_version, compose_dir: nil)
      compose_dir ||= File.join(Dir.pwd, ".gemdock")
      compose_file = File.join(compose_dir, compose_filename(ruby_version))
      File.exist?(compose_file)
    end

    # Remove the compose file for the given Ruby version
    #
    # @param ruby_version [String] Ruby version
    # @param compose_dir [String] Directory containing compose file
    # @return [Boolean] true if file was removed or didn't exist
    def deprovision(ruby_version, compose_dir: nil)
      compose_dir ||= File.join(Dir.pwd, ".gemdock")
      compose_file = File.join(compose_dir, compose_filename(ruby_version))

      unless File.exist?(compose_file)
        logger.debug("Compose file not found", compose_file: compose_file)
        return true
      end

      logger.info("Deprovisioning container", {
        ruby_version: ruby_version,
        compose_file: compose_file
      })

      File.delete(compose_file)
      logger.info("Container deprovisioned", ruby_version: ruby_version)
      true
    rescue => e
      logger.error("Failed to deprovision container", {
        ruby_version: ruby_version,
        error: e.message
      })
      false
    end

    # Get the compose file path for a Ruby version
    #
    # @param ruby_version [String] Ruby version
    # @param compose_dir [String] Directory containing compose files
    # @return [String] Path to compose file
    def compose_file_path(ruby_version, compose_dir: nil)
      compose_dir ||= File.join(Dir.pwd, ".gemdock")
      File.join(compose_dir, compose_filename(ruby_version))
    end

    private

    # Generate the docker-compose configuration
    #
    # @param ruby_version [String] Ruby version
    # @param project_path [String] Project directory path
    # @return [Hash] Docker Compose configuration
    def generate_compose_config(ruby_version, project_path)
      container_name = Utils.container_name(ruby_version)
      volume_name = Utils.volume_name(ruby_version)

      {
        "version" => "3.8",
        "services" => {
          "ruby" => {
            "image" => "ruby:#{ruby_version}",
            "container_name" => container_name,
            "working_dir" => "/app",
            "command" => "sleep infinity",
            "volumes" => [
              "#{project_path}:/app",
              "#{volume_name}:/usr/local/bundle"
            ],
            "environment" => {
              "BUNDLE_PATH" => "/usr/local/bundle",
              "GEM_HOME" => "/usr/local/bundle",
              "BUNDLE_APP_CONFIG" => "/usr/local/bundle"
            },
            "networks" => ["gemdock"]
          }
        },
        "volumes" => {
          volume_name => {
            "name" => volume_name
          }
        },
        "networks" => {
          "gemdock" => {
            "name" => "gemdock_network"
          }
        }
      }
    end

    # Write the compose configuration to a file
    #
    # @param compose_file [String] Path to compose file
    # @param config [Hash] Compose configuration
    def write_compose_file(compose_file, config)
      yaml_content = YAML.dump(config)
      
      # Write atomically using temp file
      temp_file = "#{compose_file}.tmp"
      File.write(temp_file, yaml_content)
      File.rename(temp_file, compose_file)
      
      logger.debug("Wrote compose file", {
        path: compose_file,
        size: File.size(compose_file)
      })
    rescue => e
      File.delete(temp_file) if File.exist?(temp_file)
      logger.error("Failed to write compose file", {
        path: compose_file,
        error: e.message
      })
      raise
    end

    # Generate the compose filename for a Ruby version
    #
    # @param ruby_version [String] Ruby version
    # @return [String] Compose filename
    def compose_filename(ruby_version)
      sanitized = Utils.sanitize_version(ruby_version)
      "docker-compose-#{sanitized}.yml"
    end

    # Validate the project path exists
    #
    # @param project_path [String] Path to validate
    # @raise [ArgumentError] if path doesn't exist or isn't a directory
    def validate_project_path!(project_path)
      unless File.exist?(project_path)
        raise ArgumentError, "Project path does not exist: #{project_path}"
      end

      unless File.directory?(project_path)
        raise ArgumentError, "Project path is not a directory: #{project_path}"
      end
    end
  end
end
