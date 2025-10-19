# @author Saiqul Haq <saiqulhaq@gmail.com>

require "thor"
require "fileutils"
require "yaml"
require "shellwords"
require "net/http"
require "json"

module GemDock
  class CLI < Thor
    # class << self
    #   # Hackery. Take the exec method away from Thor so that we can redefine it.
    #   # https://github.com/ddollar/foreman/issues/655#issuecomment-263188152
    #   def is_thor_reserved_word?(word, type)
    #     return false if word == "exec"

    #     super
    #   end

    #   def exit_on_failure?
    #     true
    #   end
    # end

    desc "exec COMMAND [ARGS...]", "Execute arbitrary commands in the container"
    method_option :ruby_version, type: :string, aliases: "-r", desc: "Ruby version to use (e.g., 3.2.0, 2.7.0)"
    def exec(*args)
      if args.empty?
        puts "Error: No command specified"
        puts "Usage: gemdock exec [--ruby-version VERSION] <command> [args...]"
        puts "Example: gemdock exec gem install bundler 2.4.22"
        puts "         gemdock exec --ruby-version 3.2.0 bundle gem myproject"
        puts "         gemdock exec shell  # Opens an interactive shell"
        exit 1
      end

      ruby_version = options[:ruby_version] || default_ruby_version
      ensure_initialized(ruby_version)

      # Handle special 'shell' command
      if args.first == "shell"
        run_shell(ruby_version)
      else
        run_command(args, ruby_version)
      end
    end

    private

    def ensure_initialized(ruby_version)
      compose_file = docker_compose_file_path(ruby_version)
      unless File.exist?(compose_file)
        puts "Initializing GemDock with Ruby version #{ruby_version}..."
        initialize_gemdock(ruby_version)
      end
    end

    def initialize_gemdock(ruby_version)
      create_gemdock_directory
      create_docker_compose_yml(ruby_version: ruby_version)
      puts "GemDock initialized successfully with Ruby version #{ruby_version}!"
    end

    def run_shell(ruby_version)
      command = build_docker_compose_command(ruby_version, interactive: true)
      command << ["run", "--rm", "gem-app", "/bin/bash"]
      system(*command.flatten)
    end

    def run_command(args, ruby_version)
      command = build_docker_compose_command(ruby_version)
      command << ["run", "--rm", "gem-app", "bash", "-c", args.join(" ")]
      system(*command.flatten)
    end

    def build_docker_compose_command(ruby_version, interactive: false)
      cmd = ["docker", "compose"]
      cmd << ["-f", docker_compose_file_path(ruby_version)]
      
      if interactive
        # For interactive shell, we need TTY allocation
        cmd
      else
        cmd
      end
    end

    def create_gemdock_directory
      FileUtils.mkdir_p(gemdock_dir)
    end

    # add an argument to the method to accept Ruby version to use in docker compose file
    def create_docker_compose_yml(ruby_version:)
      path = docker_compose_file_path(ruby_version)
      content = docker_compose_yml_content(ruby_version: ruby_version)
      File.write(path, content)
    end

    def gemdock_dir
      File.join(ENV["HOME"], ".gemdock")
    end

    def docker_compose_file_path(ruby_version)
      # Sanitize version for filename (e.g., "3.3.0" -> "3_3_0")
      sanitized_version = sanitize_version(ruby_version)
      File.join(gemdock_dir, "docker-compose-ruby-#{sanitized_version}.yml")
    end

    def sanitize_version(version)
      version.gsub('.', '_').gsub('-', '_')
    end

    def docker_compose_yml_content(ruby_version:)
      # Sanitize version for volume name (e.g., "3.3.0" -> "3_3_0")
      volume_suffix = sanitize_version(ruby_version)
      volume_name = "bundler_data_ruby_#{volume_suffix}"

      <<~YAML
        services:
          gem-app:
            image: ruby:#{ruby_version}
            environment:
              - HISTFILE=/app/tmp/.bash_history
              - BUNDLE_PATH=/bundle
              - BUNDLE_CONFIG=/app/.bundle/config
            command: bash
            working_dir: /app
            volumes:
              - ${SOURCE_DIR:-#{Dir.pwd}}:/app:cached
              - #{volume_name}:/bundle
            tmpfs:
              - /tmp
            stdin_open: true
            tty: true

        volumes:
          #{volume_name}:
      YAML
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
