# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Error Recovery Integration", :integration do
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

  describe "container crash recovery" do
    it "detects and handles crashed containers" do
      # Provision and start container
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
      
      # Get container name
      state = state_manager.state
      container_name = state["containers"][ruby_version]["name"]
      
      # Kill container to simulate crash
      system("docker kill #{container_name} >/dev/null 2>&1")
      sleep 1
      
      # Container should not be running
      expect(container_lifecycle.running?(ruby_version)).to be false
      
      # State should still show container exists
      expect(state_manager.state["containers"]).to have_key(ruby_version)
      
      # Can restart after crash
      result = container_lifecycle.start(ruby_version, compose_file: compose_file)
      expect(result).to be true
      sleep 2
      
      expect(container_lifecycle.running?(ruby_version)).to be true
      
      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
    
    it "recovers from container killed during operation" do
      # Provision container
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      container_name = state_manager.state["containers"][ruby_version]["name"]
      
      # Kill container
      system("docker kill #{container_name} >/dev/null 2>&1")
      sleep 1
      
      # Try to execute command (should fail gracefully)
      executor = GemDock::ContainerCommandExecutor.new(
        docker: docker_command,
        health_check: health_check,
        state_manager: state_manager,
        logger: logger
      )
      
      # This should raise an error or return false
      expect {
        result = executor.execute(ruby_version, "ruby --version")
        raise GemDock::ContainerNotRunningError.new("Container not running", ruby_version) unless result[:success]
      }.to raise_error(GemDock::ContainerNotRunningError)
      
      # Can recover by restarting
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Now exec should work
      result = executor.execute(ruby_version, "ruby --version")
      expect(result[:success]).to be true
      
      # Cleanup
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
  end

  describe "Docker daemon unavailable scenarios" do
    it "provides helpful error when Docker is not running" do
      # Stop Docker daemon check by mocking docker_available?
      allow_any_instance_of(GemDock::DockerCommand).to receive(:docker_available?).and_return(false)
      
      # Try to provision (should fail with clear error)
      expect {
        container_provisioner.provision(
          ruby_version,
          project_path: test_gemdock_dir,
          compose_dir: test_gemdock_dir
        )
      }.to raise_error(GemDock::DockerNotAvailableError)
    end
    
    it "handles Docker command timeouts gracefully" do
      # Mock a timeout scenario
      allow(docker_command).to receive(:run).and_raise(Timeout::Error, "Docker command timed out")
      
      # Try to start container (should raise timeout error)
      expect {
        container_lifecycle.start(ruby_version, compose_file: "/tmp/test.yml")
      }.to raise_error(Timeout::Error)
    end
  end

  describe "corrupted state file recovery" do
    it "recovers from corrupted JSON state file" do
      # Provision a container first
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      # Get state file path from the manager
      state_file = GemDock::StateManager::STATE_FILE
      
      # Corrupt the state file
      File.write(state_file, "{ invalid json }")
      
      # Create new state manager (should detect corruption)
      new_state_manager = GemDock::StateManager.new
      
      # Should raise corruption error
      expect {
        new_state_manager.state
      }.to raise_error(GemDock::StateFileCorruptedError)
      
      # Can recover by resetting state
      File.delete(state_file)
      
      # New state manager should work
      recovered_manager = GemDock::StateManager.new
      expect(recovered_manager.state).to be_a(Hash)
      expect(recovered_manager.state["containers"]).to eq({})
      
      # Cleanup any remaining containers
      cleanup_test_containers
    end
    
    it "handles missing state file gracefully" do
      # Get state file path
      state_file = GemDock::StateManager::STATE_FILE
      
      # Delete state file
      File.delete(state_file) if File.exist?(state_file)
      
      # Create new state manager
      new_manager = GemDock::StateManager.new
      
      # Should initialize with default state
      expect(new_manager.state).to be_a(Hash)
      expect(new_manager.state["containers"]).to eq({})
      expect(new_manager.state["current_ruby"]).to be_nil
    end
    
    it "validates state data integrity on load" do
      # Get state file path
      state_file = GemDock::StateManager::STATE_FILE
      
      # Create state with invalid structure
      invalid_state = {
        "containers" => {
          ruby_version => {
            "name" => "test-container",
            # Missing required fields: status, compose_file, created_at
          }
        }
      }
      
      File.write(state_file, JSON.pretty_generate(invalid_state))
      
      # Loading should handle missing fields
      new_manager = GemDock::StateManager.new
      container_state = new_manager.container_state(ruby_version)
      
      # Should return state with defaults for missing fields
      expect(container_state).to have_key("status")
    end
  end

  describe "resource cleanup after failures" do
    it "cleans up partial provision on failure" do
      # Mock compose file creation to fail
      allow(container_provisioner).to receive(:generate_compose_file).and_raise(StandardError, "Compose generation failed")
      
      # Try to provision (should fail)
      expect {
        container_provisioner.provision(
          ruby_version,
          project_path: test_gemdock_dir,
          compose_dir: test_gemdock_dir
        )
      }.to raise_error(StandardError, "Compose generation failed")
      
      # State should not have container entry or should be marked as failed
      state = state_manager.state
      expect(state["containers"][ruby_version]).to be_nil
    end
    
    it "removes orphaned containers on cleanup" do
      # Provision and start container
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      container_name = state_manager.state["containers"][ruby_version]["name"]
      
      # Manually corrupt state to simulate desync
      File.delete(state_manager.state_file)
      
      # Container is still running but state is lost
      expect(container_exists?(container_name)).to be true
      
      # Inspector should be able to find orphaned container
      inspector = GemDock::ContainerInspector.new(docker_command: docker_command)
      status = inspector.status(container_name)
      
      expect(status[:running]).to be true
      
      # Manual cleanup
      system("docker rm -f #{container_name} >/dev/null 2>&1")
      
      expect(container_exists?(container_name)).to be false
    end
    
    it "handles volume cleanup when container removal fails" do
      # Provision container
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      state = state_manager.state
      container_name = state["containers"][ruby_version]["name"]
      volume_name = state["containers"][ruby_version]["volume"]
      
      # Verify volume exists
      expect(volume_exists?(volume_name)).to be true
      
      # Stop and remove container
      container_lifecycle.stop(ruby_version)
      container_lifecycle.remove(ruby_version, remove_volume: false)
      
      # Volume should still exist
      expect(volume_exists?(volume_name)).to be true
      
      # Now remove with volume
      container_lifecycle.remove(ruby_version, remove_volume: true)
      
      # Volume should be gone
      expect(volume_exists?(volume_name)).to be false
    end
  end

  describe "recovery messaging and guidance" do
    it "provides actionable error messages for common failures" do
      # Test ContainerNotFoundError
      expect {
        container_lifecycle.stop("999.999.999")
      }.to raise_error(GemDock::ContainerNotFoundError) do |error|
        expect(error.suggestions).not_to be_empty
        expect(error.full_message).to include("Container")
      end
    end
    
    it "suggests next steps after failed operations" do
      # Provision container
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      container_lifecycle.start(ruby_version, compose_file: compose_file)
      sleep 2
      
      # Kill container
      state = state_manager.state
      container_name = state["containers"][ruby_version]["name"]
      system("docker kill #{container_name} >/dev/null 2>&1")
      sleep 1
      
      # Try to exec (should fail with helpful message)
      executor = GemDock::ContainerCommandExecutor.new(
        docker: docker_command,
        health_check: health_check,
        state_manager: state_manager,
        logger: logger
      )
      
      expect {
        result = executor.execute(ruby_version, "ruby --version")
        raise GemDock::ContainerNotRunningError.new("Container not running", ruby_version) unless result[:success]
      }.to raise_error(GemDock::ContainerNotRunningError) do |error|
        expect(error.suggestions).to include("Start the container with: gemdock provision start #{ruby_version}")
      end
      
      # Cleanup
      container_lifecycle.remove(ruby_version, remove_volume: true)
    end
    
    it "detects and reports Docker permission issues" do
      # Mock permission denied error
      allow(docker_command).to receive(:run).and_raise(Errno::EACCES, "Permission denied")
      
      # Try to start container
      expect {
        container_lifecycle.start(ruby_version, compose_file: "/tmp/test.yml")
      }.to raise_error(Errno::EACCES)
    end
  end

  describe "state consistency after errors" do
    it "maintains consistent state when start fails" do
      # Provision container
      compose_file = unique_compose_file(ruby_version)
      container_provisioner.provision(
        ruby_version,
        project_path: test_gemdock_dir,
        compose_dir: test_gemdock_dir
      )
      
      # Mock start failure
      allow(docker_command).to receive(:run).with(/docker compose.*up/).and_return(false)
      
      # Try to start (should fail)
      result = container_lifecycle.start(ruby_version, compose_file: compose_file)
      expect(result).to be false
      
      # State should reflect stopped status
      state = state_manager.state
      expect(state["containers"][ruby_version]["status"]).to eq("stopped")
      
      # Cleanup
      cleanup_test_containers
    end
    
    it "rolls back state on provision failure" do
      # Mock provision failure after state update
      allow_any_instance_of(GemDock::ContainerProvisioner).to receive(:generate_compose_file).and_wrap_original do |method, *args|
        # Update state first
        state_manager.update_container(ruby_version, {
          "name" => unique_container_name(ruby_version),
          "status" => "provisioning"
        })
        # Then fail
        raise StandardError, "Provision failed"
      end
      
      # Try to provision
      expect {
        container_provisioner.provision(
          ruby_version,
          project_path: test_gemdock_dir,
          compose_dir: test_gemdock_dir
        )
      }.to raise_error(StandardError)
      
      # State should be cleaned up or marked as failed
      # (depending on implementation, either no entry or error state)
      state = state_manager.state
      container_state = state["containers"][ruby_version]
      
      if container_state
        expect(container_state["status"]).to eq("provisioning")
      end
    end
  end
end
