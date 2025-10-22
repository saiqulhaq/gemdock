# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Auto-Provisioning Integration", :integration do
  let(:ruby_version) { "3.2.0" }
  let(:managers) { create_test_managers }
  let(:state_manager) { managers[:state_manager] }
  let(:config_manager) { managers[:config_manager] }
  let(:docker_command) { managers[:docker_command] }
  let(:health_check) { managers[:health_check] }
  let(:logger) { managers[:logger] }

  let(:container_lifecycle) do
    GemDock::ContainerLifecycle.new(
      docker: docker_command,
      health_check: health_check,
      state_manager: state_manager,
      logger: logger
    )
  end

  let(:container_provisioner) do
    GemDock::ContainerProvisioner.new(logger: logger)
  end

  let(:auto_provisioner) do
    GemDock::AutoProvisioner.new(
      provisioner: container_provisioner,
      lifecycle: container_lifecycle,
      config_manager: config_manager,
      state_manager: state_manager,
      logger: logger
    )
  end

  describe "first-time user flow with auto-provision" do
    it "prompts user and provisions on confirmation" do
      skip_unless_docker_available
      
      # Mock user saying yes
      allow(GemDock::PromptHelper).to receive(:yes_no).and_return(true)
      
      # Mock ci_mode? to return false so tty_available? returns true
      allow(auto_provisioner).to receive(:ci_mode?).and_return(false)
      # Mock tty_available? directly since it also checks $stdin.tty? and $stdout.tty?
      allow(auto_provisioner).to receive(:tty_available?).and_return(true)

      # Configure auto-provision disabled (to test prompting)
      config_manager.set("auto_provision", false)

      # Ensure ready should provision
      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)

      expect(result).to be true

      # Verify PromptHelper was called
      expect(GemDock::PromptHelper).to have_received(:yes_no)

      # Verify container was provisioned and started
      state = state_manager.state
      expect(state["containers"]).to have_key(ruby_version)
      expect(state["containers"][ruby_version]["status"]).to eq("running")

      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end

    it "skips provisioning when user declines" do
      # Mock user saying no
      allow(GemDock::PromptHelper).to receive(:yes_no).and_return(false)
      # Mock TTY to enable prompting
      allow(auto_provisioner).to receive(:tty_available?).and_return(true)

      # Configure auto-provision disabled
      config_manager.set("auto_provision", false)

      # Ensure ready should return false
      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)

      expect(result).to be false

      # Verify container was NOT provisioned
      state = state_manager.state
      expect(state["containers"]).not_to have_key(ruby_version)
    end

    it "auto-provisions without prompting when auto_provision is enabled" do
      # Configure auto-provision enabled
      config_manager.set("auto_provision", true)

      # Should not call PromptHelper
      expect(GemDock::PromptHelper).not_to receive(:yes_no)

      # Ensure ready should provision automatically
      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)

      expect(result).to be true

      # Verify container was provisioned and started
      state = state_manager.state
      expect(state["containers"]).to have_key(ruby_version)
      expect(state["containers"][ruby_version]["status"]).to eq("running")

      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
  end

  describe "stopped container auto-restart" do
    it "automatically restarts stopped container" do
      # Provision and start
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )

      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2

      # Verify running
      expect(container_lifecycle.running?(ruby_version)).to be true

      # Stop container manually
      container_lifecycle.stop(ruby_version)
      expect(container_lifecycle.running?(ruby_version)).to be false

      # Enable auto-provision
      config_manager.set("auto_provision", true)

      # Ensure ready should restart
      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)

      expect(result).to be true

      # Verify container is running again
      sleep 2
      expect(container_lifecycle.running?(ruby_version)).to be true

      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
  end

  describe "version switching with resource management" do
    let(:version_1) { "3.2.0" }
    let(:version_2) { "3.1.4" }

    it "provisions and switches between versions" do
      config_manager.set("auto_provision", true)

      # Provision first version
      result_1 = auto_provisioner.ensure_ready(version_1, project_path: test_gemdock_dir)
      expect(result_1).to be true
      sleep 2

      # Verify first version is running
      expect(container_lifecycle.running?(version_1)).to be true
      expect(state_manager.state["current_ruby"]).to eq(version_1)

      # Switch to second version
      result_2 = auto_provisioner.ensure_ready(version_2, project_path: test_gemdock_dir)
      expect(result_2).to be true
      sleep 2

      # Verify second version is running
      expect(container_lifecycle.running?(version_2)).to be true
      expect(state_manager.state["current_ruby"]).to eq(version_2)

      # First version should still be running (no auto-stop)
      expect(container_lifecycle.running?(version_1)).to be true

      # Cleanup both
      container_lifecycle.stop(version_1)
      container_lifecycle.remove(version_1, remove_volume: true)
      container_lifecycle.stop(version_2)
      container_lifecycle.remove(version_2, remove_volume: true)
    end
  end

  describe "CI/CD mode (no prompts)" do
    it "respects CI environment variable and skips prompts" do
      # Simulate CI environment
      stub_const("ENV", ENV.to_hash.merge("CI" => "true"))

      # Disable auto-provision (would normally prompt)
      config_manager.set("auto_provision", false)

      # Should not prompt in CI mode
      expect(GemDock::PromptHelper).not_to receive(:yes_no)

      # In CI mode with auto_provision false, should return false
      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)

      expect(result).to be false
    end

    it "auto-provisions in CI mode when auto_provision is enabled" do
      # Simulate CI environment
      stub_const("ENV", ENV.to_hash.merge("CI" => "true"))

      # Enable auto-provision
      config_manager.set("auto_provision", true)

      # Should not prompt
      expect(GemDock::PromptHelper).not_to receive(:yes_no)

      # Should provision automatically
      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)

      expect(result).to be true

      # Verify container was provisioned
      state = state_manager.state
      expect(state["containers"]).to have_key(ruby_version)

      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
  end

  describe "configuration-driven behavior" do
    it "uses mode configuration for container behavior" do
      # Set persistent mode
      config_manager.set("mode", "persistent")
      config_manager.set("auto_provision", true)

      result = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)
      expect(result).to be true

      sleep 2

      # In persistent mode, container should use sleep infinity
      state = state_manager.state
      container_name = state["containers"][ruby_version]["name"]

      # Check container command
      command_output = `docker inspect #{container_name} --format='{{.Config.Cmd}}' 2>/dev/null`.strip
      expect(command_output).to include("sleep")

      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
  end

  describe "idempotency" do
    it "is safe to call ensure_ready multiple times" do
      config_manager.set("auto_provision", true)

      # First call - provisions
      result_1 = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)
      expect(result_1).to be true
      sleep 2

      container_name_1 = state_manager.state["containers"][ruby_version]["name"]

      # Second call - should be idempotent
      result_2 = auto_provisioner.ensure_ready(ruby_version, project_path: test_gemdock_dir)
      expect(result_2).to be true

      container_name_2 = state_manager.state["containers"][ruby_version]["name"]

      # Should be same container
      expect(container_name_1).to eq(container_name_2)

      # Should still be running
      expect(container_lifecycle.running?(ruby_version)).to be true

      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
  end
end
