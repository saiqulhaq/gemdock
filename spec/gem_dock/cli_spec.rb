# @author Saiqul Haq <saiqulhaq@gmail.com>
# frozen_string_literal: true

require "spec_helper"
require "fakefs/spec_helpers"

RSpec.describe GemDock::CLI do
  include FakeFS::SpecHelpers

  let(:cli) do
    described_class.new
  end

  let(:default_ruby_version) { "3.2.2" }

  before do
    FakeFS.activate!
    FileUtils.mkdir_p(Dir.pwd)
    allow(ENV).to receive(:[]).with("THOR_SHELL").and_return(nil)
    allow(ENV).to receive(:[]).with("HOME").and_return("/home/user")
    allow(cli).to receive(:default_ruby_version).and_return(default_ruby_version)
  end

  after do
    FakeFS.deactivate!
  end

  describe "#exec" do
    context "when docker-compose.yml does not exist" do
      it "initializes gemdock automatically with default Ruby version" do
        allow(cli).to receive(:system).and_return(true)

        cli.exec("gem", "install", "bundler")

        expected_file = File.join(cli.send(:gemdock_dir), "docker-compose-ruby-3_2_2.yml")
        expect(File).to exist(expected_file)
      end

      it "initializes gemdock with specified Ruby version" do
        allow(cli).to receive(:system).and_return(true)
        cli.options = { ruby_version: "3.1.0" }

        cli.exec("bundle", "install")

        expected_file = File.join(cli.send(:gemdock_dir), "docker-compose-ruby-3_1_0.yml")
        expect(File).to exist(expected_file)
      end
    end

    context "when docker-compose.yml exists" do
      before do
        cli.send(:initialize_gemdock, default_ruby_version)
      end

      it "runs arbitrary commands in container" do
        expect(cli).to receive(:system) do |*args|
          command = args.flatten.join(" ")
          expect(command).to include("docker")
          expect(command).to include("compose")
          expect(command).to include("docker-compose-ruby-3_2_2.yml")
          expect(command).to include("run")
          expect(command).to include("gem install bundler")
        end

        cli.exec("gem", "install", "bundler")
      end

      it "opens interactive shell when 'shell' is passed" do
        expect(cli).to receive(:system) do |*args|
          command = args.flatten.join(" ")
          expect(command).to include("docker")
          expect(command).to include("compose")
          expect(command).to include("docker-compose-ruby-3_2_2.yml")
          expect(command).to include("run")
          expect(command).to include("/bin/bash")
        end

        cli.exec("shell")
      end

      it "runs rspec commands" do
        expect(cli).to receive(:system) do |*args|
          command = args.flatten.join(" ")
          expect(command).to include("rspec spec/")
        end

        cli.exec("rspec", "spec/")
      end
    end

    context "with --ruby-version flag" do
      it "uses the specified Ruby version" do
        allow(cli).to receive(:system).and_return(true)
        cli.options = { ruby_version: "2.7.0" }

        cli.exec("bundle", "install")

        expected_file = File.join(cli.send(:gemdock_dir), "docker-compose-ruby-2_7_0.yml")
        expect(File).to exist(expected_file)
        
        # Check that the file contains the correct Ruby version
        content = File.read(expected_file)
        expect(content).to include("ruby:2.7.0")
        expect(content).to include("bundler_data_ruby_2_7_0")
      end

      it "creates version-specific volume names" do
        allow(cli).to receive(:system).and_return(true)
        cli.options = { ruby_version: "3.3.0" }

        cli.exec("gem", "list")

        expected_file = File.join(cli.send(:gemdock_dir), "docker-compose-ruby-3_3_0.yml")
        content = File.read(expected_file)
        expect(content).to include("bundler_data_ruby_3_3_0")
      end

      it "allows switching between different Ruby versions" do
        allow(cli).to receive(:system).and_return(true)

        # First command with Ruby 3.2.0
        cli.options = { ruby_version: "3.2.0" }
        cli.exec("bundle", "install")

        file_3_2 = File.join(cli.send(:gemdock_dir), "docker-compose-ruby-3_2_0.yml")
        expect(File).to exist(file_3_2)

        # Second command with Ruby 2.7.0
        cli.options = { ruby_version: "2.7.0" }
        cli.exec("bundle", "install")

        file_2_7 = File.join(cli.send(:gemdock_dir), "docker-compose-ruby-2_7_0.yml")
        expect(File).to exist(file_2_7)

        # Both files should exist
        expect(File).to exist(file_3_2)
        expect(File).to exist(file_2_7)
      end
    end

    context "when no command is provided" do
      it "prints usage information and exits" do
        expect { cli.exec }.to raise_error(SystemExit)
      end
    end
  end
end
