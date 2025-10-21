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
  let(:container_inspector) { instance_double(GemDock::ContainerInspector) }

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
    allow(GemDock::ContainerInspector).to receive(:new).and_return(container_inspector)

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

  describe "#switch" do
    before do
      allow(GemDock::Utils).to receive(:valid_ruby_version?).and_return(true)
      allow(state_manager).to receive(:container_provisioned?).and_return(true)
      allow(state_manager).to receive(:set_current_ruby)
      allow(config_manager).to receive(:set)
      allow(container_lifecycle).to receive(:running?).and_return(true)
    end

    it "switches to a valid provisioned version" do
      expect(state_manager).to receive(:set_current_ruby).with("3.1.0")
      expect(config_manager).to receive(:set).with("default_ruby_version", "3.1.0")
      expect($stdout).to receive(:puts).with("Switched default Ruby version to 3.1.0")
      cli.invoke(:switch, ["3.1.0"])
    end

    it "shows container status after switching" do
      allow(container_lifecycle).to receive(:running?).with("3.1.0").and_return(true)
      expect($stdout).to receive(:puts).with("Container is running and ready to use")
      cli.invoke(:switch, ["3.1.0"])
    end

    it "notifies when container is stopped" do
      allow(container_lifecycle).to receive(:running?).with("3.1.0").and_return(false)
      expect($stdout).to receive(:puts).with(/Container is stopped/)
      cli.invoke(:switch, ["3.1.0"])
    end

    context "with invalid version format" do
      it "rejects invalid version and exits" do
        allow(GemDock::Utils).to receive(:valid_ruby_version?).and_return(false)
        expect($stdout).to receive(:puts).with("Error: Invalid Ruby version format 'invalid'")
        expect { cli.invoke(:switch, ["invalid"]) }.to raise_error(SystemExit)
      end
    end

    context "when container is not provisioned" do
      it "shows error and exits" do
        allow(state_manager).to receive(:container_provisioned?).and_return(false)
        expect($stdout).to receive(:puts).with("Error: Container for Ruby 3.1.0 is not provisioned")
        expect { cli.invoke(:switch, ["3.1.0"]) }.to raise_error(SystemExit)
      end
    end

    context "when switching fails" do
      it "handles errors gracefully" do
        allow(state_manager).to receive(:set_current_ruby).and_raise(StandardError.new("State error"))
        expect { cli.invoke(:switch, ["3.1.0"]) }.to raise_error(SystemExit)
      end
    end
  end

  describe "#current" do
    it "shows current Ruby version when set" do
      allow(state_manager).to receive(:state).and_return({ "current_ruby" => "3.2.0" })
      allow(config_manager).to receive(:get).with("default_ruby_version").and_return(nil)
      allow(container_lifecycle).to receive(:running?).with("3.2.0").and_return(true)
      expect($stdout).to receive(:puts).with("Current Ruby version: 3.2.0")
      expect($stdout).to receive(:puts).with("Status: running")
      cli.invoke(:current)
    end

    it "shows stopped status when container is not running" do
      allow(state_manager).to receive(:state).and_return({ "current_ruby" => "3.2.0" })
      allow(config_manager).to receive(:get).with("default_ruby_version").and_return(nil)
      allow(container_lifecycle).to receive(:running?).with("3.2.0").and_return(false)
      expect($stdout).to receive(:puts).with("Status: stopped")
      cli.invoke(:current)
    end

    it "shows default version when no current version" do
      allow(state_manager).to receive(:state).and_return({})
      allow(config_manager).to receive(:get).with("default_ruby_version").and_return("3.2.0")
      expect($stdout).to receive(:puts).with("Default Ruby version: 3.2.0 (not yet used)")
      cli.invoke(:current)
    end

    it "shows message when no version is set" do
      allow(state_manager).to receive(:state).and_return({})
      allow(config_manager).to receive(:get).with("default_ruby_version").and_return(nil)
      expect($stdout).to receive(:puts).with("No Ruby version set")
      cli.invoke(:current)
    end
  end

  describe "#clean" do
    let(:container_cleanup) { instance_double(GemDock::ContainerCleanup) }

    before do
      allow(GemDock::ContainerCleanup).to receive(:new).and_return(container_cleanup)
    end

    context "with no containers to clean" do
      it "displays statistics and reports no cleanup needed" do
        allow(container_cleanup).to receive(:cleanup_stats).and_return({
          total_containers: 2,
          running_containers: 1,
          stopped_containers: 1,
          idle_containers: 0,
          idle_timeout_hours: 24
        })
        allow(container_cleanup).to receive(:cleanup).and_return({
          cleaned: 0,
          skipped: 0,
          failed: 0
        })

        expect($stdout).to receive(:puts).with("Container Statistics:")
        expect($stdout).to receive(:puts).with(/No containers were cleaned/)

        cli.invoke(:clean)
      end
    end

    context "with containers to clean" do
      it "displays cleanup results" do
        allow(container_cleanup).to receive(:cleanup_stats).and_return({
          total_containers: 3,
          running_containers: 1,
          stopped_containers: 2,
          idle_containers: 1,
          idle_timeout_hours: 24
        })
        allow(container_cleanup).to receive(:cleanup).and_return({
          cleaned: 1,
          skipped: 0,
          failed: 0
        })

        expect($stdout).to receive(:puts).with("Container Statistics:")
        expect($stdout).to receive(:puts).with(/Cleanup complete/)
        expect($stdout).to receive(:puts).with(/Cleaned: 1/)

        cli.invoke(:clean)
      end
    end

    context "with --dry-run flag" do
      it "shows what would be cleaned" do
        allow(container_cleanup).to receive(:cleanup_stats).and_return({
          total_containers: 2,
          running_containers: 0,
          stopped_containers: 2,
          idle_containers: 1,
          idle_timeout_hours: 24
        })
        allow(container_cleanup).to receive(:cleanup).and_return({
          cleaned: 0,
          skipped: 1,
          failed: 0,
          dry_run: true
        })

        expect($stdout).to receive(:puts).with(/Dry run complete/)

        cli.invoke(:clean, [], dry_run: true)
      end
    end

    context "with --all flag" do
      it "passes the all flag to cleanup" do
        allow(container_cleanup).to receive(:cleanup_stats).and_return({
          total_containers: 2,
          running_containers: 0,
          stopped_containers: 2,
          idle_containers: 0,
          idle_timeout_hours: 24
        })
        expect(container_cleanup).to receive(:cleanup).with(
          all: true,
          force: false,
          dry_run: false
        ).and_return({
          cleaned: 2,
          skipped: 0,
          failed: 0
        })

        cli.invoke(:clean, [], all: true)
      end
    end

    context "with --force flag" do
      it "passes the force flag to cleanup" do
        allow(container_cleanup).to receive(:cleanup_stats).and_return({
          total_containers: 2,
          running_containers: 0,
          stopped_containers: 2,
          idle_containers: 1,
          idle_timeout_hours: 24
        })
        expect(container_cleanup).to receive(:cleanup).with(
          all: false,
          force: true,
          dry_run: false
        ).and_return({
          cleaned: 1,
          skipped: 0,
          failed: 0
        })

        cli.invoke(:clean, [], force: true)
      end
    end

    context "with failures" do
      it "reports failed cleanups" do
        allow(container_cleanup).to receive(:cleanup_stats).and_return({
          total_containers: 3,
          running_containers: 0,
          stopped_containers: 3,
          idle_containers: 2,
          idle_timeout_hours: 24
        })
        allow(container_cleanup).to receive(:cleanup).and_return({
          cleaned: 1,
          skipped: 0,
          failed: 1
        })

        expect($stdout).to receive(:puts).with(/Failed: 1/)

        cli.invoke(:clean)
      end
    end
  end

  describe "#status" do
    let(:project_status) do
      {
        current_ruby_version: "3.2.0",
        current_container_status: {
          running: true,
          status_icon: "✅",
          health_status: :healthy,
          health_icon: "💚"
        },
        docker_available: true,
        compose_available: true,
        total_containers: 2,
        running_containers: 1
      }
    end

    before do
      allow(container_inspector).to receive(:project_status).and_return(project_status)
    end

    it "displays project status" do
      formatted_status = "Project Status\nCurrent Ruby: 3.2.0"
      allow(container_inspector).to receive(:format_project_status).with(project_status).and_return(formatted_status)

      expect($stdout).to receive(:puts).with(formatted_status)

      cli.invoke(:status)
    end

    it "handles errors gracefully" do
      allow(container_inspector).to receive(:project_status).and_raise(StandardError.new("Docker not available"))

      expect { cli.invoke(:status) }.to raise_error(SystemExit)
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
