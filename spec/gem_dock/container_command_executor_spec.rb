require "spec_helper"
require "gem_dock/container_command_executor"

RSpec.xdescribe GemDock::ContainerCommandExecutor do
  let(:docker) { instance_double(GemDock::DockerCommand) }
  let(:health_check) { instance_double(GemDock::ContainerHealthCheck) }
  let(:state_manager) { instance_double(GemDock::StateManager) }
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }
  
  let(:executor) do
    described_class.new(
      docker: docker,
      health_check: health_check,
      state_manager: state_manager,
      logger: logger
    )
  end

  let(:ruby_version) { "3.2.0" }
  let(:container_id) { "abc123def456" }
  let(:healthy_status) do
    GemDock::ContainerHealthCheck::HealthStatus.new(:healthy, "3.2.0", "OK", Time.now)
  end
  let(:unhealthy_status) do
    GemDock::ContainerHealthCheck::HealthStatus.new(:unhealthy, nil, "Unresponsive", Time.now)
  end

  describe "#execute" do
    context "when container is running and healthy" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).with(container_id).and_return(healthy_status)
      end

      it "executes the command successfully" do
        allow(docker).to receive(:execute).and_return({
          success: true,
          output: "command output",
          stderr: "",
          exit_code: 0
        })

        result = executor.execute(ruby_version, "bundle install")

        expect(result[:success]).to be true
        expect(result[:output]).to eq("command output")
      end

      it "builds correct docker exec command" do
        allow(docker).to receive(:execute).and_return({
          success: true, output: "", stderr: "", exit_code: 0
        })

        executor.execute(ruby_version, "gem list")

        expect(docker).to have_received(:execute).with(
          "exec #{container_id} sh -c gem list",
          capture_output: true
        )
      end

      it "returns exit code from docker" do
        allow(docker).to receive(:execute).and_return({
          success: false,
          output: "",
          stderr: "error",
          exit_code: 127
        })

        result = executor.execute(ruby_version, "nonexistent_command")

        expect(result[:exit_code]).to eq(127)
      end

      it "logs successful execution" do
        allow(docker).to receive(:execute).and_return({
          success: true, output: "", stderr: "", exit_code: 0
        })

        executor.execute(ruby_version, "bundle install")

        expect(logger).to have_received(:info).with(
          "Command executed successfully",
          hash_including(ruby_version: ruby_version, exit_code: 0)
        )
      end

      it "logs failed execution" do
        allow(docker).to receive(:execute).and_return({
          success: false, output: "", stderr: "error", exit_code: 1
        })

        executor.execute(ruby_version, "bad_command")

        expect(logger).to have_received(:warn).with(
          "Command failed",
          hash_including(ruby_version: ruby_version, exit_code: 1)
        )
      end
    end

    context "with working directory" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).and_return(healthy_status)
        allow(docker).to receive(:execute).and_return({
          success: true, output: "", stderr: "", exit_code: 0
        })
      end

      it "includes workdir in command" do
        executor.execute(ruby_version, "ls", workdir: "/app/lib")

        expect(docker).to have_received(:execute).with(
          "exec -w /app/lib #{container_id} sh -c ls",
          capture_output: true
        )
      end
    end

    context "with environment variables" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).and_return(healthy_status)
        allow(docker).to receive(:execute).and_return({
          success: true, output: "", stderr: "", exit_code: 0
        })
      end

      it "includes env vars in command" do
        executor.execute(ruby_version, "env", env: { "DEBUG" => "true", "LOG_LEVEL" => "debug" })

        expect(docker).to have_received(:execute).with(
          "exec -e DEBUG=true -e LOG_LEVEL=debug #{container_id} sh -c env",
          capture_output: true
        )
      end
    end

    context "with streaming output" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).and_return(healthy_status)
        allow(docker).to receive(:execute).and_return({
          success: true, output: "", stderr: "", exit_code: 0
        })
      end

      it "sets capture_output to false" do
        executor.execute(ruby_version, "bundle install", stream_output: true)

        expect(docker).to have_received(:execute).with(
          anything,
          capture_output: false
        )
      end
    end

    context "without health check" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check)
        allow(docker).to receive(:execute).and_return({
          success: true, output: "", stderr: "", exit_code: 0
        })
      end

      it "skips health check when disabled" do
        executor.execute(ruby_version, "echo test", check_health: false)

        expect(health_check).not_to have_received(:check)
      end
    end

    context "when container is not running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "stopped", container_id: container_id })
      end

      it "returns failure without executing" do
        result = executor.execute(ruby_version, "bundle install")

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("not running")
      end

      it "does not execute docker command" do
        allow(docker).to receive(:execute)

        executor.execute(ruby_version, "bundle install")

        expect(docker).not_to have_received(:execute)
      end

      it "logs error" do
        executor.execute(ruby_version, "bundle install")

        expect(logger).to have_received(:error).with(
          "Container not running",
          hash_including(ruby_version: ruby_version, 'status' => "stopped")
        )
      end
    end

    context "when container is unhealthy" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).and_return(unhealthy_status)
      end

      it "returns failure without executing" do
        result = executor.execute(ruby_version, "bundle install")

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("health check failed")
      end

      it "logs health check failure" do
        executor.execute(ruby_version, "bundle install")

        expect(logger).to have_received(:error).with(
          "Container health check failed",
          hash_including(
            ruby_version: ruby_version,
            container_id: container_id,
            status: :unhealthy
          )
        )
      end
    end

    context "when container is not provisioned" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "not_provisioned" })
      end

      it "returns failure" do
        result = executor.execute(ruby_version, "bundle install")

        expect(result[:success]).to be false
      end
    end
  end

  describe "#execute_interactive" do
    context "when container is running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
      end

      it "executes interactive command using system()" do
        allow(executor).to receive(:system).and_return(true)

        exit_code = executor.execute_interactive(ruby_version, command: "bash")

        expect(executor).to have_received(:system).with("exec -it #{container_id} bash")
        expect(exit_code).to eq(0)
      end

      it "includes workdir when specified" do
        allow(executor).to receive(:system).and_return(true)

        executor.execute_interactive(ruby_version, command: "bash", workdir: "/app")

        expect(executor).to have_received(:system).with("exec -it -w /app #{container_id} bash")
      end

      it "returns exit code from system" do
        # Mock system to simulate a failure
        allow(executor).to receive(:system) do
          # Set $? to simulate exit status
          `false` # This sets $? to a failed status
          false
        end

        exit_code = executor.execute_interactive(ruby_version)

        expect(exit_code).to be > 0
      end

      it "logs session start and end" do
        allow(executor).to receive(:system).and_return(true)

        executor.execute_interactive(ruby_version)

        expect(logger).to have_received(:info).with(
          "Starting interactive session",
          hash_including(ruby_version: ruby_version)
        )
        expect(logger).to have_received(:info).with(
          "Interactive session ended",
          hash_including(ruby_version: ruby_version)
        )
      end
    end

    context "when container is not running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "stopped", container_id: container_id })
      end

      it "returns exit code 1 without executing" do
        exit_code = executor.execute_interactive(ruby_version)

        expect(exit_code).to eq(1)
      end

      it "logs error" do
        executor.execute_interactive(ruby_version)

        expect(logger).to have_received(:error).with(
          "Container not running",
          hash_including(ruby_version: ruby_version, 'status' => "stopped")
        )
      end
    end
  end

  describe "#ready?" do
    context "when container is running and healthy" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).with(container_id).and_return(healthy_status)
      end

      it "returns true" do
        expect(executor.ready?(ruby_version)).to be true
      end
    end

    context "when container is not running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "stopped", container_id: container_id })
      end

      it "returns false" do
        expect(executor.ready?(ruby_version)).to be false
      end
    end

    context "when container is running but unhealthy" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: container_id })
        allow(health_check).to receive(:check).with(container_id).and_return(unhealthy_status)
      end

      it "returns false" do
        expect(executor.ready?(ruby_version)).to be false
      end
    end
  end
end
