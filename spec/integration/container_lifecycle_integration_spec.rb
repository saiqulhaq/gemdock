# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "yaml"
require "tmpdir"

RSpec.describe "Container Lifecycle Integration", :integration do
  let(:ruby_version) { "3.2.0" }
  let(:managers) { create_test_managers }
  let(:state_manager) { managers[:state_manager] }
  let(:config_manager) { managers[:config_manager] }
  let(:docker_command) { managers[:docker_command] }
  let(:health_check) { managers[:health_check] }
  
  let(:container_lifecycle) do
    GemDock::ContainerLifecycle.new(
      docker_command: docker_command,
      health_check: health_check,
      state_manager: state_manager
    )
  end
  
  let(:container_provisioner) do
    GemDock::ContainerProvisioner.new(
      docker_command: docker_command,
      state_manager: state_manager
    )
  end
  
  let(:container_cleanup) do
    GemDock::ContainerCleanup.new(
      docker_command: docker_command,
      state_manager: state_manager,
      config_manager: config_manager,
      lifecycle: container_lifecycle
    )
  end

  describe "complete provision → start → exec → stop → clean cycle" do
    it "provisions, starts, executes commands, stops, and cleans up a container" do
      # 1. Provision container
      compose_file = unique_compose_file(ruby_version)
      result = container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      expect(result).to be true
      expect(File.exist?(compose_file)).to be true
      
      # Verify state was updated
      state = state_manager.state
      expect(state["containers"]).to have_key(ruby_version)
      expect(state["containers"][ruby_version]["status"]).to eq("provisioned")
      
      # 2. Start container
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      
      # Wait for container to be fully running
      sleep 2
      
      # Verify container is running
      expect(container_lifecycle.running?(ruby_version)).to be true
      
      # Verify state reflects running status
      state = state_manager.state
      expect(state["containers"][ruby_version]["status"]).to eq("running")
      expect(state["containers"][ruby_version]["last_used"]).not_to be_nil
      
      # 3. Execute command in container
      container_name = state["containers"][ruby_version]["name"]
      command_result = exec_in_container(container_name, "ruby --version")
      
      expect(command_result).to include("ruby")
      expect(command_result).to include(ruby_version)
      
      # 4. Stop container
      container_lifecycle.stop(ruby_version)
      
      # Verify container is stopped
      expect(container_lifecycle.running?(ruby_version)).to be false
      
      # Verify state reflects stopped status
      state = state_manager.state
      expect(state["containers"][ruby_version]["status"]).to eq("stopped")
      
      # 5. Clean up container
      results = container_cleanup.cleanup(all: true, force: true)
      
      expect(results[:cleaned]).to be >= 1
      
      # Verify container is removed
      expect(container_exists?(container_name)).to be false
      
      # Verify state is updated
      state = state_manager.state
      expect(state["containers"]).not_to have_key(ruby_version)
    end
  end

  describe "multiple Ruby version isolation" do
    let(:ruby_version_1) { "3.2.0" }
    let(:ruby_version_2) { "3.1.4" }
    
    it "provisions and manages multiple Ruby versions independently" do
      # Provision first version
      compose_file_1 = unique_compose_file(ruby_version_1)
      result_1 = container_provisioner.provision(
        ruby_version_1,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      expect(result_1).to be true
      
      # Provision second version
      compose_file_2 = unique_compose_file(ruby_version_2)
      result_2 = container_provisioner.provision(
        ruby_version_2,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      expect(result_2).to be true
      
      # Verify both are in state
      state = state_manager.state
      expect(state["containers"]).to have_key(ruby_version_1)
      expect(state["containers"]).to have_key(ruby_version_2)
      expect(state["containers"][ruby_version_1]["name"]).not_to eq(state["containers"][ruby_version_2]["name"])
      
      # Start both containers
      container_lifecycle.start(ruby_version_1, compose_file: compose_file_1)
      container_lifecycle.start(ruby_version_2, compose_file: compose_file_2)
      
      sleep 2
      
      # Verify both are running
      expect(container_lifecycle.running?(ruby_version_1)).to be true
      expect(container_lifecycle.running?(ruby_version_2)).to be true
      
      # Verify each container has the correct Ruby version
      container_1_name = state_manager.state["containers"][ruby_version_1]["name"]
      container_2_name = state_manager.state["containers"][ruby_version_2]["name"]
      
      version_output_1 = exec_in_container(container_1_name, "ruby --version")
      version_output_2 = exec_in_container(container_2_name, "ruby --version")
      
      expect(version_output_1).to include(ruby_version_1)
      expect(version_output_2).to include(ruby_version_2)
      
      # Stop and clean up
      container_lifecycle.stop(ruby_version_1)
      container_lifecycle.stop(ruby_version_2)
      container_cleanup.cleanup(all: true, force: true)
    end
  end

  describe "state persistence across operations" do
    it "maintains state consistency through start/stop cycles" do
      # Provision
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      # Start
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Record state
      initial_state = state_manager.state.dup
      container_name = initial_state["containers"][ruby_version]["name"]
      
      # Stop
      container_lifecycle.stop(ruby_version)
      
      # Verify state still has container info
      stopped_state = state_manager.state
      expect(stopped_state["containers"][ruby_version]["name"]).to eq(container_name)
      expect(stopped_state["containers"][ruby_version]["status"]).to eq("stopped")
      
      # Restart
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Verify state restored correctly
      restarted_state = state_manager.state
      expect(restarted_state["containers"][ruby_version]["name"]).to eq(container_name)
      expect(restarted_state["containers"][ruby_version]["status"]).to eq("running")
      expect(restarted_state["containers"][ruby_version]["last_used"]).not_to eq(initial_state["containers"][ruby_version]["last_used"])
      
      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_cleanup.cleanup(all: true, force: true)
    end
  end

  describe "Docker Compose file generation" do
    it "generates valid Docker Compose files with correct configuration" do
      compose_file = unique_compose_file(ruby_version)
      
      # Provision
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      # Verify compose file exists
      expect(File.exist?(compose_file)).to be true
      
      # Parse and verify compose file content
      compose_content = YAML.load_file(compose_file)
      
      expect(compose_content).to have_key("services")
      expect(compose_content["services"]).to have_key("gemdock")
      
      service = compose_content["services"]["gemdock"]
      expect(service["image"]).to include("ruby")
      expect(service["image"]).to include(ruby_version)
      expect(service["command"]).to eq("sleep infinity")
      expect(service["volumes"]).to be_an(Array)
      expect(service["volumes"].any? { |v| v.include?("gem_volume") }).to be true
      
      # Cleanup
      container_cleanup.cleanup(all: true, force: true)
    end
  end

  describe "volume persistence and cleanup" do
    it "creates persistent volumes and cleans them up correctly" do
      compose_file = unique_compose_file(ruby_version)
      
      # Provision and start
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Get container and volume name
      state = state_manager.state
      container_name = state["containers"][ruby_version]["name"]
      volume_name = state["containers"][ruby_version]["volume_name"]
      
      # Verify volume exists
      expect(volume_exists?(volume_name)).to be true
      
      # Write data to volume
      exec_in_container(container_name, "mkdir -p /usr/local/bundle/test")
      exec_in_container(container_name, "echo 'test data' > /usr/local/bundle/test/file.txt")
      
      # Stop container
      container_lifecycle.stop(ruby_version)
      
      # Verify volume still exists after stop
      expect(volume_exists?(volume_name)).to be true
      
      # Restart and verify data persists
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      data_output = exec_in_container(container_name, "cat /usr/local/bundle/test/file.txt")
      expect(data_output.strip).to eq("test data")
      
      # Clean up with volume removal
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
      
      # Verify volume is removed
      expect(volume_exists?(volume_name)).to be false
    end
  end

  describe "error handling during lifecycle operations" do
    it "handles non-existent container gracefully" do
      expect {
        container_lifecycle.stop("999.999.999")
      }.to raise_error(StandardError)
    end
    
    it "handles start when already running" do
      compose_file = unique_compose_file(ruby_version)
      
      # Provision and start
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Try to start again - should not error
      expect {
        container_lifecycle.start(ruby_version, compose_file: compose_file)
      }.not_to raise_error
      
      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_cleanup.cleanup(all: true, force: true)
    end
    
    it "handles stop when already stopped" do
      compose_file = unique_compose_file(ruby_version)
      
      # Provision and start
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Stop
      container_lifecycle.stop(ruby_version)
      
      # Try to stop again - should not error
      expect {
        container_lifecycle.stop(ruby_version)
      }.not_to raise_error
      
      # Cleanup
      container_cleanup.cleanup(all: true, force: true)
    end
  end
end
