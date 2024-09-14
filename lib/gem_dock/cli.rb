# @author Saiqul Haq <saiqulhaq@gmail.com>

require "thor"
require "fileutils"
require "yaml"
require "shellwords"
require "net/http"
require "json"

module GemDock
  class CLI < Thor
    class << self
      # Hackery. Take the run method away from Thor so that we can redefine it.
      # https://github.com/ddollar/foreman/issues/655#issuecomment-263188152
      def is_thor_reserved_word?(word, type)
        return false if word == "run"

        super
      end

      def exit_on_failure?
        true
      end
    end

    desc "init [RUBY_VERSION]", "Initialize GemDock in the current project"
    method_option :ruby_version, type: :string, desc: "Ruby version to use in docker compose file. It will check the latest stable version from the internet if not provided."
    def init(ruby_version = options[:ruby_version])
      ruby_version = default_ruby_version if ruby_version.nil?

      create_gemdock_directory
      create_dip_yml
      create_docker_compose_yml(ruby_version: ruby_version)
      puts "GemDock initialized successfully with Ruby version #{ruby_version}!"
    end

    desc "update", "Update docker-compose.yml file"
    method_option :ruby_version, type: :string, desc: "Ruby version to use in docker compose file. It will check the latest stable version from the internet if not provided."
    def update(ruby_version = options[:ruby_version])
      ruby_version = default_ruby_version if ruby_version.nil?
      create_docker_compose_yml(ruby_version: ruby_version)
      puts "docker-compose.yml updated successfully!"
    end

    desc "provision", "Run dip provision"
    def provision
      system("DIP_FILE=#{dip_file_path} dip provision")
    end

    desc "run COMMAND", "Run a dip command"
    # @param commands [Array] command and parameters to run
    def run(*commands)
      escaped_commands = commands.map { |cmd| Shellwords.escape(cmd) }.join(' ')
      system("DIP_FILE=#{Shellwords.escape(dip_file_path)} dip run #{escaped_commands}")
    end

    desc "ls", "List all available dip commands"
    def ls
      system("DIP_FILE=#{dip_file_path} dip ls")
    end

    private

    def create_gemdock_directory
      FileUtils.mkdir_p(gemdock_dir)
    end

    def create_dip_yml
      File.write(File.join(gemdock_dir, "dip.yml"), dip_yml_content)
    end

    # add an argument to the method to accept Ruby version to use in docker compose file
    def create_docker_compose_yml(ruby_version: default_ruby_version)
      path = File.join(gemdock_dir, "docker-compose.yml")
      content = docker_compose_yml_content(ruby_version: ruby_version)
      File.write(path, content)
    end

    def gemdock_dir
      File.join(ENV["HOME"], ".dip", project_path)
    end

    def project_path
      Dir.pwd.sub("#{ENV["HOME"]}/", "")
    end

    def dip_file_path
      File.join(gemdock_dir, "dip.yml")
    end

    def dip_yml_content
      <<~YAML
        version: '8.0'

        compose:
          files:
            - docker-compose.yml

        interaction:
          bash:
            description: Open the Bash shell in app's container
            service: gem-app
            command: /bin/bash

          bundle:
            description: Run Bundler commands
            service: gem-app
            command: bundle

          appraisal:
            description: Run Appraisal commands
            service: gem-app
            command: bundle exec appraisal

          rspec:
            description: Run Rspec commands
            service: gem-app
            command: bundle exec rspec

        provision:
          - dip compose down --volumes
          - rm -f Gemfile.lock gemfiles/*
          - dip bundle install
          # - dip appraisal install
      YAML
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
