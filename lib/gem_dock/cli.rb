# @author Saiqul Haq <saiqulhaq@gmail.com>

require "thor"
require "fileutils"
require "yaml"

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

    desc "init", "Initialize GemDock in the current project"
    def init
      create_gemdock_directory
      create_dip_yml
      create_docker_compose_yml
      puts "GemDock initialized successfully!"
    end

    desc "provision", "Run dip provision"
    def provision
      system("DIP_FILE=#{dip_file_path} dip provision")
    end

    desc "run COMMAND", "Run a dip command"
    def run(command)
      system("DIP_FILE=#{dip_file_path} dip run #{command}")
    end

    private

    def create_gemdock_directory
      FileUtils.mkdir_p(gemdock_dir)
    end

    def create_dip_yml
      File.write(File.join(gemdock_dir, "dip.yml"), dip_yml_content)
    end

    def create_docker_compose_yml
      File.write(File.join(gemdock_dir, "docker-compose.yml"), docker_compose_yml_content)
    end

    def gemdock_dir
      File.join(ENV["HOME"], ".dip", project_path)
    end

    def project_path
      Dir.pwd.sub("#{ENV['HOME']}/", "")
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

    def docker_compose_yml_content
      <<~YAML
        services:
          gem-app:
            image: ruby:${RUBY_IMAGE:-3.2}
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
  end
end
