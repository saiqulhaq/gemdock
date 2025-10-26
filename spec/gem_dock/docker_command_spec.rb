require "spec_helper"
require "gem_dock/docker_command"

RSpec.describe GemDock::DockerCommand do
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:docker) { described_class.new(logger: logger) }

  describe "#execute" do
    context "with successful command" do
      it "returns success result with output" do
        # Mock Open3.capture3 to simulate successful docker command
        allow(Open3).to receive(:capture3).with("docker version --format '{{.Server.Version}}'")
          .and_return(["20.10.17\n", "", instance_double(Process::Status, success?: true, exitstatus: 0)])

        result = docker.execute("version --format '{{.Server.Version}}'")

        expect(result[:success]).to be true
        expect(result[:output]).to eq("20.10.17\n")
        expect(result[:stderr]).to eq("")
        expect(result[:exit_code]).to eq(0)
      end

      it "logs command execution" do
        allow(Open3).to receive(:capture3).and_return(["output", "", instance_double(Process::Status, success?: true, exitstatus: 0)])

        docker.execute("ps")

        expect(logger).to have_received(:info).with("Executing Docker command", hash_including(command: "docker ps"))
        expect(logger).to have_received(:info).with("Docker command completed", hash_including(success: true))
      end
    end

    context "with failed command" do
      it "returns failure result with stderr" do
        allow(Open3).to receive(:capture3).with("docker invalid-command")
          .and_return(["", "unknown command: invalid-command\n", instance_double(Process::Status, success?: false, exitstatus: 1)])

        result = docker.execute("invalid-command")

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("unknown command")
        expect(result[:exit_code]).to eq(1)
      end

      it "logs failure" do
        allow(Open3).to receive(:capture3).and_return(["", "error", instance_double(Process::Status, success?: false, exitstatus: 1)])

        docker.execute("invalid")

        expect(logger).to have_received(:info).with("Docker command completed", hash_including(success: false, exit_code: 1))
      end
    end

    context "with timeout" do
      it "raises TimeoutError when command exceeds timeout" do
        allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

        expect { docker.execute("long-command", timeout: 1) }.to raise_error(
          GemDock::DockerCommand::TimeoutError,
          /timed out after 1 seconds/
        )
      end

      it "logs timeout error" do
        allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

        begin
          docker.execute("long-command", timeout: 1)
        rescue GemDock::DockerCommand::TimeoutError
          # Expected
        end

        expect(logger).to have_received(:error).with("Docker command timed out", hash_including(timeout: 1))
      end
    end

    context "with custom timeout" do
      it "uses provided timeout value" do
        allow(Open3).to receive(:capture3).and_return(["output", "", instance_double(Process::Status, success?: true, exitstatus: 0)])
        
        expect(Timeout).to receive(:timeout).with(60).and_call_original

        docker.execute("build .", timeout: 60)
      end
    end

    context "with streaming output" do
      it "streams output in real-time" do
        # Mock Open3.popen3 for streaming
        stdin = instance_double(IO, close: nil)
        stdout = StringIO.new("line1\nline2\n")
        stderr = StringIO.new("")
        wait_thr = instance_double(Process::Waiter, value: instance_double(Process::Status, exitstatus: 0))

        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)
        
        result = docker.execute("logs container", capture_output: false)

        expect(result[:success]).to be true
        expect(result[:output]).to include("line1", "line2")
      end
    end
  end

  describe "#compose" do
    it "executes docker compose commands" do
      allow(Open3).to receive(:capture3).with("docker compose up -d")
        .and_return(["Container started\n", "", instance_double(Process::Status, success?: true, exitstatus: 0)])

      result = docker.compose("up -d")

      expect(result[:success]).to be true
      expect(result[:output]).to include("Container started")
    end

    it "uses longer timeout for compose commands" do
      allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true, exitstatus: 0)])
      
      expect(Timeout).to receive(:timeout).with(300).and_call_original

      docker.compose("up -d")
    end
  end

  describe "#docker_available?" do
    context "when docker is available" do
      it "returns true" do
        allow(Open3).to receive(:capture3).with("docker info")
          .and_return(["Docker info...", "", instance_double(Process::Status, success?: true, exitstatus: 0)])

        expect(docker.docker_available?).to be true
      end
    end

    context "when docker is not available" do
      it "returns false" do
        allow(Open3).to receive(:capture3).with("docker info")
          .and_return(["", "Cannot connect to Docker daemon", instance_double(Process::Status, success?: false, exitstatus: 1)])

        expect(docker.docker_available?).to be false
      end

      it "logs warning" do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT.new("docker command not found"))

        docker.docker_available?

        expect(logger).to have_received(:warn).with("Docker not available", hash_including(:error))
      end
    end
  end

  describe "#compose_available?" do
    context "when docker compose is available" do
      it "returns true" do
        allow(Open3).to receive(:capture3).with("docker compose version")
          .and_return(["Docker Compose version v2.10.0", "", instance_double(Process::Status, success?: true, exitstatus: 0)])

        expect(docker.compose_available?).to be true
      end
    end

    context "when docker compose is not available" do
      it "returns false" do
        allow(Open3).to receive(:capture3).with("docker compose version")
          .and_return(["", "unknown command: compose", instance_double(Process::Status, success?: false, exitstatus: 1)])

        expect(docker.compose_available?).to be false
      end
    end
  end

  describe "error handling" do
    it "includes command in error details" do
      allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

      begin
        docker.execute("test-command")
      rescue GemDock::DockerCommand::TimeoutError => e
        expect(e.command).to eq("docker test-command")
      end
    end
  end
end
