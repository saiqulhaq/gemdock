require "spec_helper"
require "gem_dock/container_lifecycle"
require "tmpdir"

RSpec.describe GemDock::ContainerLifecycle do
  let(:docker) { instance_double(GemDock::DockerCommand) }
  let(:health_check) { instance_double(GemDock::ContainerHealthCheck) }
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:state_manager) { instance_double(GemDock::StateManager) }
  let(:lifecycle) do
    described_class.new(
      docker: docker,
      health_check: health_check,
      state_manager: state_manager,
      logger: logger
    )
  end

  let(:ruby_version) { "3.2.0" }
  let(:container_name) { "gemdock-ruby-3_2_0" }
  let(:container_id) { "abc123def456" }
  let(:compose_file) { "docker-compose.yml" }

  describe "#start" do
    let(:healthy_status) do
      GemDock::ContainerHealthCheck::HealthStatus.new(:healthy, "3.2.0", "OK", Time.now)
    end

    context "when container is not running" do
      before do
        # Mock state checks
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "not_provisioned" })

        # Mock docker compose up
        allow(docker).to receive(:compose).with("up -d", timeout: 300)
          .and_return({ success: true, output: "Container started", exit_code: 0 })

        # Mock getting container ID
        allow(docker).to receive(:execute)
          .with("ps -aq --filter name=^#{container_name}$", timeout: 5)
          .and_return({ success: true, output: container_id, exit_code: 0 })

        # Mock health check
        allow(health_check).to receive(:check).with(container_id, use_cache: false)
          .and_return(healthy_status)

        # Mock state update
        allow(state_manager).to receive(:update_container)
      end

      it "starts the container successfully" do
        result = lifecycle.start(ruby_version, compose_file: compose_file)

        expect(result).to be true
        expect(docker).to have_received(:compose).with("up -d", timeout: 300)
      end

      it "updates state to running" do
        lifecycle.start(ruby_version, compose_file: compose_file)

        expect(state_manager).to have_received(:update_container).with(
          ruby_version,
          hash_including("status" => "running", "container_id" => container_id)
        )
      end

      it "performs health check" do
        lifecycle.start(ruby_version, compose_file: compose_file)

        expect(health_check).to have_received(:check).with(container_id, use_cache: false)
      end

      it "logs successful start" do
        lifecycle.start(ruby_version, compose_file: compose_file)

        expect(logger).to have_received(:info).with("Starting container", hash_including(ruby_version: ruby_version))
        expect(logger).to have_received(:info).with("Container started successfully", hash_including(ruby_version: ruby_version))
      end
    end

    context "when container is already running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "running", container_id: container_id })
        allow(docker).to receive(:compose)
      end

      it "returns true without starting again" do
        result = lifecycle.start(ruby_version, compose_file: compose_file)

        expect(result).to be true
        expect(docker).not_to have_received(:compose)
      end
    end

    context "when docker compose fails" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "not_provisioned" })

        allow(docker).to receive(:compose)
          .and_return({ success: false, stderr: "compose error", exit_code: 1 })
      end

      it "returns false" do
        result = lifecycle.start(ruby_version, compose_file: compose_file)

        expect(result).to be false
      end

      it "logs error" do
        lifecycle.start(ruby_version, compose_file: compose_file)

        expect(logger).to have_received(:error).with("Failed to start container", hash_including(error: "compose error"))
      end
    end

    context "when container starts but is unhealthy" do
      let(:unhealthy_status) do
        GemDock::ContainerHealthCheck::HealthStatus.new(:unhealthy, nil, "Unresponsive", Time.now)
      end

      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "not_provisioned" })
        allow(docker).to receive(:compose).and_return({ success: true, output: "", exit_code: 0 })
        allow(docker).to receive(:execute)
          .with("ps -aq --filter name=^#{container_name}$", timeout: 5)
          .and_return({ success: true, output: container_id, exit_code: 0 })
        allow(health_check).to receive(:check).and_return(unhealthy_status)
        allow(state_manager).to receive(:update_container)
      end

      it "returns false" do
        result = lifecycle.start(ruby_version, compose_file: compose_file)

        expect(result).to be false
      end
    end
  end

  describe "#stop" do
    context "when container is running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "running", container_id: container_id })

        allow(docker).to receive(:execute)
          .with("stop --time 30 #{container_id}", timeout: 40)
          .and_return({ success: true, output: container_id, exit_code: 0 })

        allow(state_manager).to receive(:update_container)
      end

      it "stops the container successfully" do
        result = lifecycle.stop(ruby_version)

        expect(result).to be true
        expect(docker).to have_received(:execute).with("stop --time 30 #{container_id}", timeout: 40)
      end

      it "updates state to stopped" do
        lifecycle.stop(ruby_version)

        expect(state_manager).to have_received(:update_container).with(
          ruby_version,
          hash_including("status" => "stopped")
        )
      end

      it "logs successful stop" do
        lifecycle.stop(ruby_version)

        expect(logger).to have_received(:info).with("Stopping container", hash_including(ruby_version: ruby_version))
        expect(logger).to have_received(:info).with("Container stopped successfully", ruby_version: ruby_version)
      end
    end

    context "when container is already stopped" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "stopped", container_id: container_id })
        allow(docker).to receive(:execute)
      end

      it "returns true without stopping again" do
        result = lifecycle.stop(ruby_version)

        expect(result).to be true
        expect(docker).not_to have_received(:execute)
      end
    end

    context "when container is not provisioned" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "not_provisioned" })
        allow(docker).to receive(:execute)
      end

      it "returns true without action" do
        result = lifecycle.stop(ruby_version)

        expect(result).to be true
        expect(docker).not_to have_received(:execute)
      end
    end

    context "when stop fails" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "running", container_id: container_id })

        allow(docker).to receive(:execute)
          .and_return({ success: false, stderr: "stop error", exit_code: 1 })
      end

      it "returns false" do
        result = lifecycle.stop(ruby_version)

        expect(result).to be false
      end

      it "logs error" do
        lifecycle.stop(ruby_version)

        expect(logger).to have_received(:error).with("Failed to stop container", hash_including(error: "stop error"))
      end
    end
  end

  describe "#restart" do
    before do
      # First call for stop - container is running
      # Second call for start - container is now stopped after stop
      allow(state_manager).to receive(:container_state).with(ruby_version)
        .and_return(
          { status: "running", container_id: container_id },
          { status: "stopped", container_id: container_id }
        )

      # Mock stop
      allow(docker).to receive(:execute)
        .with("stop --time 30 #{container_id}", timeout: 40)
        .and_return({ success: true, output: "", exit_code: 0 })

      # Mock start
      allow(docker).to receive(:compose)
        .and_return({ success: true, output: "", exit_code: 0 })

      allow(docker).to receive(:execute)
        .with("ps -aq --filter name=^#{container_name}$", timeout: 5)
        .and_return({ success: true, output: container_id, exit_code: 0 })

      # Mock health check
      healthy_status = GemDock::ContainerHealthCheck::HealthStatus.new(:healthy, "3.2.0", "OK", Time.now)
      allow(health_check).to receive(:check).and_return(healthy_status)

      allow(state_manager).to receive(:update_container)
    end

    it "stops and starts the container" do
      result = lifecycle.restart(ruby_version, compose_file: compose_file)

      expect(result).to be true
      expect(docker).to have_received(:execute).with("stop --time 30 #{container_id}", timeout: 40)
      expect(docker).to have_received(:compose)
    end

    it "verifies health after restart" do
      lifecycle.restart(ruby_version, compose_file: compose_file)

      expect(health_check).to have_received(:check).with(container_id, use_cache: false).twice
    end

    it "logs restart operation" do
      lifecycle.restart(ruby_version, compose_file: compose_file)

      expect(logger).to have_received(:info).with("Restarting container", ruby_version: ruby_version)
      expect(logger).to have_received(:info).with("Container restarted successfully", ruby_version: ruby_version)
    end
  end

  describe "#remove" do
    let(:volume_name) { "bundler_data_ruby_3_2_0" }

    context "when removing container with volume" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "running", container_id: container_id })

        # Mock stop
        allow(docker).to receive(:execute)
          .with("stop --time 30 #{container_id}", timeout: 40)
          .and_return({ success: true, output: "", exit_code: 0 })

        # Mock remove container
        allow(docker).to receive(:execute)
          .with("rm -f #{container_id}", timeout: 30)
          .and_return({ success: true, output: "", exit_code: 0 })

        # Mock remove volume
        allow(docker).to receive(:execute)
          .with("volume rm #{volume_name}", timeout: 30)
          .and_return({ success: true, output: "", exit_code: 0 })

        allow(state_manager).to receive(:update_container)
      end

      it "removes container and volume" do
        result = lifecycle.remove(ruby_version, remove_volume: true)

        expect(result).to be true
        expect(docker).to have_received(:execute).with("rm -f #{container_id}", timeout: 30)
        expect(docker).to have_received(:execute).with("volume rm #{volume_name}", timeout: 30)
      end

      it "updates state to not_provisioned" do
        lifecycle.remove(ruby_version, remove_volume: true)

        expect(state_manager).to have_received(:update_container).with(
          ruby_version,
          hash_including("status" => "not_provisioned", "container_id" => nil)
        )
      end

      it "stops running container first" do
        lifecycle.remove(ruby_version, remove_volume: true)

        expect(docker).to have_received(:execute).with("stop --time 30 #{container_id}", timeout: 40)
      end
    end

    context "when removing container without volume" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "stopped", container_id: container_id })

        allow(docker).to receive(:execute)
          .with("rm -f #{container_id}", timeout: 30)
          .and_return({ success: true, output: "", exit_code: 0 })

        allow(state_manager).to receive(:update_container)
      end

      it "removes only container" do
        result = lifecycle.remove(ruby_version, remove_volume: false)

        expect(result).to be true
        expect(docker).to have_received(:execute).with("rm -f #{container_id}", timeout: 30)
        expect(docker).not_to have_received(:execute).with("volume rm #{volume_name}", timeout: 30)
      end
    end

    context "when container is not provisioned" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ status: "not_provisioned" })
        allow(docker).to receive(:execute)
      end

      it "returns true without action" do
        result = lifecycle.remove(ruby_version, remove_volume: true)

        expect(result).to be true
        expect(docker).not_to have_received(:execute)
      end
    end
  end

  describe "#running?" do
    it "returns true when container is running" do
      allow(state_manager).to receive(:container_running?).with(ruby_version)
        .and_return(true)

      expect(lifecycle.running?(ruby_version)).to be true
    end

    it "returns false when container is stopped" do
      allow(state_manager).to receive(:container_running?).with(ruby_version)
        .and_return(false)

      expect(lifecycle.running?(ruby_version)).to be false
    end
  end

  describe "#provisioned?" do
    it "returns true when container is provisioned" do
      allow(state_manager).to receive(:container_provisioned?).with(ruby_version)
        .and_return(true)

      expect(lifecycle.provisioned?(ruby_version)).to be true
    end

    it "returns false when container is not provisioned" do
      allow(state_manager).to receive(:container_provisioned?).with(ruby_version)
        .and_return(false)

      expect(lifecycle.provisioned?(ruby_version)).to be false
    end
  end
end
