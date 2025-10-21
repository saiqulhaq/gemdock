# frozen_string_literal: true

require "spec_helper"
require "gem_dock/cli"

RSpec.describe GemDock::CLI do
  let(:auto_provisioner) { instance_double(GemDock::AutoProvisioner) }
  let(:command_executor) { instance_double(GemDock::ContainerCommandExecutor) }
  let(:container_lifecycle) { instance_double(GemDock::ContainerLifecycle) }
  let(:container_provisioner) { instance_double(GemDock::ContainerProvisioner) }
  let(:health_check) { instance_double(GemDock::ContainerHealthCheck) }
  let(:docker_command) { instance_double(GemDock::DockerCommand) }
  let(:state_manager) { instance_double(GemDock::StateManager) }
  let(:config_manager) { instance_double(GemDock::ConfigManager) }

  let(:cli) { described_class.new }

  before do
    # Mock dependencies
    allow(GemDock::AutoProvisioner).to receive(:new).and_return(auto_provisioner)
    allow(GemDock::ContainerCommandExecutor).to receive(:new).and_return(command_executor)
    allow(GemDock::ContainerLifecycle).to receive(:new).and_return(container_lifecycle)
    allow(GemDock::ContainerProvisioner).to receive(:new).and_return(container_provisioner)
    allow(GemDock::ContainerHealthCheck).to receive(:new).and_return(health_check)
    allow(GemDock::DockerCommand).to receive(:new).and_return(docker_command)
    allow(GemDock::StateManager).to receive(:new).and_return(state_manager)
    allow(GemDock::ConfigManager).to receive(:new).and_return(config_manager)

    # Mock default ruby version fetch to avoid network call
    stub_const("GemDock::DEFAULT_RUBY_VERSION", "3.2.0")
    allow_any_instance_of(described_class).to receive(:default_ruby_version).and_return("3.2.0")

    # Suppress output during tests
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
  end

  describe "#exec" do
    context "with no arguments" do
      it "displays error and exits" do
        expect { cli.invoke(:exec, []) }.to raise_error(SystemExit)
      end
    end

    context "with valid command" do
      before do
        allow(auto_provisioner).to receive(:ensure_ready)
        allow(command_executor).to receive(:execute).and_return(exit_code: 0, stdout: "output", stderr: "")
      end

      it "auto-provisions container before execution" do
        expect(auto_provisioner).to receive(:ensure_ready).with("3.2.0", project_path: Dir.pwd)
        cli.invoke(:exec, ["gem", "install", "bundler"])
      end

      it "executes command with streaming output" do
        expect(command_executor).to receive(:execute).with(
          "3.2.0",
          "gem install bundler",
          workdir: nil,
          stream_output: true,
          check_health: true
        )
        cli.invoke(:exec, ["gem", "install", "bundler"])
      end

      it "supports --ruby-version option" do
        expect(auto_provisioner).to receive(:ensure_ready).with("3.1.0", project_path: Dir.pwd)
        expect(command_executor).to receive(:execute).with("3.1.0", anything, anything)
        cli.invoke(:exec, ["bundle", "install"], ruby_version: "3.1.0")
      end

      it "supports --workdir option" do
        expect(command_executor).to receive(:execute).with(
          "3.2.0",
          "ls",
          workdir: "/custom/path",
          stream_output: true,
          check_health: true
        )
        cli.invoke(:exec, ["ls"], workdir: "/custom/path")
      end

      it "exits with command exit code on failure" do
        allow(command_executor).to receive(:execute).and_return(exit_code: 1, stdout: "", stderr: "error")
        expect { cli.invoke(:exec, ["false"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context "with shell command" do
      before do
        allow(auto_provisioner).to receive(:ensure_ready)
        allow(command_executor).to receive(:execute_interactive)
      end

      it "opens interactive shell" do
        expect(command_executor).to receive(:execute_interactive).with(
          "3.2.0",
          command: "/bin/bash",
          workdir: nil
        )
        cli.invoke(:exec, ["shell"])
      end

      it "supports --workdir option for shell" do
        expect(command_executor).to receive(:execute_interactive).with(
          "3.2.0",
          command: "/bin/bash",
          workdir: "/app/lib"
        )
        cli.invoke(:exec, ["shell"], workdir: "/app/lib")
      end
    end

    context "with provisioning errors" do
      it "handles provisioning cancelled error" do
        allow(auto_provisioner).to receive(:ensure_ready).and_raise(
          StandardError.new("User cancelled")
        )
        expect { cli.invoke(:exec, ["ls"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "handles provisioning failed error" do
        allow(auto_provisioner).to receive(:ensure_ready).and_raise(
          StandardError.new("Provisioning failed")
        )
        expect { cli.invoke(:exec, ["ls"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context "with container errors" do
      before do
        allow(auto_provisioner).to receive(:ensure_ready)
      end

      it "handles container not running error" do
        allow(command_executor).to receive(:execute).and_raise(
          StandardError.new("Container not running")
        )
        expect { cli.invoke(:exec, ["ls"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "handles container not healthy error" do
        allow(command_executor).to receive(:execute).and_raise(
          StandardError.new("Container unhealthy")
        )
        expect { cli.invoke(:exec, ["ls"]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end
end

RSpec.describe GemDock::Provision do
  let(:container_lifecycle) { instance_double(GemDock::ContainerLifecycle) }
  let(:container_provisioner) { instance_double(GemDock::ContainerProvisioner) }
  let(:health_check) { instance_double(GemDock::ContainerHealthCheck) }
  let(:docker_command) { instance_double(GemDock::DockerCommand) }
  let(:state_manager) { instance_double(GemDock::StateManager) }

  let(:provision) { described_class.new }

  before do
    # Mock dependencies
    allow(GemDock::ContainerLifecycle).to receive(:new).and_return(container_lifecycle)
    allow(GemDock::ContainerProvisioner).to receive(:new).and_return(container_provisioner)
    allow(GemDock::ContainerHealthCheck).to receive(:new).and_return(health_check)
    allow(GemDock::DockerCommand).to receive(:new).and_return(docker_command)
    allow(GemDock::StateManager).to receive(:new).and_return(state_manager)

    stub_const("GemDock::DEFAULT_RUBY_VERSION", "3.2.0")

    # Suppress output during tests
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdin).to receive(:gets).and_return("yes\n")
  end

  describe "#start" do
    it "starts container with default version" do
      expect(container_lifecycle).to receive(:start).with(
        "3.2.0",
        compose_file: anything
      )
      provision.invoke(:start)
    end

    it "starts container with specified version" do
      expect(container_lifecycle).to receive(:start).with(
        "3.1.0",
        compose_file: anything
      )
      provision.invoke(:start, ["3.1.0"])
    end

    it "handles container not provisioned error" do
      allow(container_lifecycle).to receive(:start).and_raise(
        StandardError.new("Not provisioned")
      )
      expect { provision.invoke(:start) }.to raise_error(SystemExit)
    end

    it "handles docker command error" do
      error = GemDock::DockerCommand::CommandError.new(
        "Start failed",
        exit_code: 1,
        stderr: "error",
        command: "docker start"
      )
      allow(container_lifecycle).to receive(:start).and_raise(error)
      expect { provision.invoke(:start) }.to raise_error(SystemExit)
    end
  end

  describe "#stop" do
    it "stops container with default version" do
      expect(container_lifecycle).to receive(:stop).with("3.2.0")
      provision.invoke(:stop)
    end

    it "stops container with specified version" do
      expect(container_lifecycle).to receive(:stop).with("3.1.0")
      provision.invoke(:stop, ["3.1.0"])
    end

    it "handles container not running error" do
      allow(container_lifecycle).to receive(:stop).and_raise(
        StandardError.new("Not running")
      )
      expect { provision.invoke(:stop) }.to raise_error(SystemExit)
    end
  end

  describe "#restart" do
    it "restarts container with default version" do
      expect(container_lifecycle).to receive(:restart).with("3.2.0", compose_file: anything)
      provision.invoke(:restart)
    end

    it "restarts container with specified version" do
      expect(container_lifecycle).to receive(:restart).with("3.1.0", compose_file: anything)
      provision.invoke(:restart, ["3.1.0"])
    end

    it "handles container not provisioned error" do
      allow(container_lifecycle).to receive(:restart).and_raise(
        StandardError.new("Not provisioned")
      )
      expect { provision.invoke(:restart) }.to raise_error(SystemExit)
    end
  end

  describe "#down" do
    it "removes container without volume by default" do
      expect(container_lifecycle).to receive(:remove).with(
        "3.2.0",
        remove_volume: false
      )
      provision.invoke(:down)
    end

    it "removes container with volume when confirmed" do
      allow($stdin).to receive(:gets).and_return("yes\n")
      expect(container_lifecycle).to receive(:remove).with(
        "3.2.0",
        remove_volume: true
      )
      provision.invoke(:down, [], remove_volume: true)
    end

    it "cancels when user does not confirm volume removal" do
      allow($stdin).to receive(:gets).and_return("no\n")
      expect(container_lifecycle).not_to receive(:remove)
      provision.invoke(:down, [], remove_volume: true)
    end

    it "handles container not provisioned error" do
      allow(container_lifecycle).to receive(:remove).and_raise(
        StandardError.new("Not provisioned")
      )
      expect { provision.invoke(:down) }.to raise_error(SystemExit)
    end
  end

  describe "#create" do
    it "provisions and starts new container" do
      expect(container_provisioner).to receive(:provision).with(
        "3.1.0",
        project_path: Dir.pwd,
        compose_dir: File.join(ENV["HOME"], ".gemdock")
      )
      expect(container_lifecycle).to receive(:start).with("3.1.0", compose_file: anything)
      provision.invoke(:create, ["3.1.0"])
    end

    it "handles provisioning error" do
      allow(container_provisioner).to receive(:provision).and_raise(
        StandardError.new("Failed to provision")
      )
      expect { provision.invoke(:create, ["3.1.0"]) }.to raise_error(SystemExit)
    end

    it "handles docker command error during start" do
      allow(container_provisioner).to receive(:provision)
      error = GemDock::DockerCommand::CommandError.new(
        "Start failed",
        exit_code: 1,
        stderr: "error",
        command: "docker start"
      )
      allow(container_lifecycle).to receive(:start).and_raise(error)
      expect { provision.invoke(:create, ["3.1.0"]) }.to raise_error(SystemExit)
    end
  end

  describe "#list" do
    before do
      allow(state_manager).to receive(:all_containers)
    end

    it "displays message when no containers exist" do
      allow(state_manager).to receive(:all_containers).and_return({})
      expect($stdout).to receive(:puts).with("No containers provisioned yet.")
      provision.invoke(:list)
    end

    it "lists containers with their status" do
      allow(state_manager).to receive(:all_containers).and_return({
        "3.2.0" => { "container_id" => "abc123", "status" => "running" },
        "3.1.0" => { "container_id" => "def456", "status" => "stopped" }
      })
      allow(container_lifecycle).to receive(:running?).with("3.2.0").and_return(true)
      allow(container_lifecycle).to receive(:running?).with("3.1.0").and_return(false)
      
      health_status = GemDock::ContainerHealthCheck::HealthStatus.new(
        status: :healthy,
        ruby_version: "3.2.0",
        message: "OK",
        checked_at: Time.now
      )
      allow(health_check).to receive(:check).and_return(health_status)

      expect($stdout).to receive(:puts).with("Provisioned containers:")
      provision.invoke(:list)
    end
  end
end
