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
    def exec(*args)
      if args.empty?
        puts "Error: No command specified"
        puts "Usage: gemdock exec <command> [args...]"
        puts "Example: gemdock exec gem install bundler 2.4.22"
        puts "         gemdock exec shell  # Opens an interactive shell"
        exit 1
      end

      ensure_initialized

      # Handle special 'shell' command
      if args.first == "shell"
        run_shell
      else
        run_command(args)
      end
    end

    private

    def ensure_initialized
      unless File.exist?(docker_compose_file_path)
        puts "GemDock not initialized. Initializing with default Ruby version..."
        initialize_gemdock
      end
    end

    def initialize_gemdock(ruby_version = nil)
      ruby_version ||= default_ruby_version
      create_gemdock_directory
      create_docker_compose_yml(ruby_version: ruby_version)
      puts "GemDock initialized successfully with Ruby version #{ruby_version}!"
    end

    def run_shell
      command = build_docker_compose_command(interactive: true)
      command << ["run", "--rm", "gem-app", "/bin/bash"]
      system(*command.flatten)
    end

    def run_command(args)
      command = build_docker_compose_command
      command << ["run", "--rm", "gem-app", "bash", "-c", args.join(" ")]
      system(*command.flatten)
    end

    def build_docker_compose_command(interactive: false)
      cmd = ["docker", "compose"]
      cmd << ["-f", docker_compose_file_path]
      
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
    def create_docker_compose_yml(ruby_version: default_ruby_version)
      path = docker_compose_file_path
      content = docker_compose_yml_content(ruby_version: ruby_version)
      File.write(path, content)
    end

    def gemdock_dir
      File.join(ENV["HOME"], ".gemdock")
    end

    def docker_compose_file_path
      File.join(gemdock_dir, "docker-compose.yml")
    end

    def docker_compose_yml_content(ruby_version: default_ruby_version)
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
              - bundler_data:/bundle
            tmpfs:
              - /tmp
            stdin_open: true
            tty: true

        volumes:
          bundler_data:
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
