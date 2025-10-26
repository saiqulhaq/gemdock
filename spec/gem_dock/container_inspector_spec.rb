# frozen_string_literal: true

require "spec_helper"
require "gem_dock/container_inspector"
require "gem_dock/docker_command"
require "gem_dock/state_manager"
require "gem_dock/container_lifecycle"
require "gem_dock/container_health_check"

RSpec.describe GemDock::ContainerInspector do
  let(:docker_command) { instance_double(GemDock::DockerCommand) }
  let(:state_manager) { instance_double(GemDock::StateManager) }
  let(:lifecycle) { instance_double(GemDock::ContainerLifecycle) }
  let(:health_check) { instance_double(GemDock::ContainerHealthCheck) }
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }

  let(:inspector) do
    described_class.new(
      docker_command: docker_command,
      state_manager: state_manager,
      lifecycle: lifecycle,
      health_check: health_check,
      logger: logger
    )
  end

  describe "#inspect_container" do
    let(:ruby_version) { "3.2.0" }
    let(:container_state) do
      {
        "container_id" => "abc123",
        "volume_name" => "gemdock-ruby-3_2_0",
        "last_used" => "2024-10-22 10:00:00",
        "created_at" => "2024-10-20 15:30:00"
      }
    end

    before do
      allow(state_manager).to receive(:container_state).with(ruby_version).and_return(container_state)
    end

    context "with running container" do
      let(:health_status) do
        GemDock::ContainerHealthCheck::HealthStatus.new(
          status: :healthy,
          ruby_version: ruby_version,
          message: "OK",
          checked_at: Time.now
        )
      end

      before do
        allow(state_manager).to receive(:container_provisioned?).with(ruby_version).and_return(true)
        allow(lifecycle).to receive(:running?).with(ruby_version).and_return(true)
        allow(health_check).to receive(:check).and_return(health_status)
        allow(docker_command).to receive(:execute).with(
          "stats --no-stream --format \"{{.MemUsage}}|{{.CPUPerc}}\" gemdock-ruby-3_2_0",
          timeout: 5
        ).and_return({
          exit_code: 0,
          stdout: "100MiB / 2GiB|5.5%\n",
          stderr: ""
        })
      end

      it "returns complete status with health and resources" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:ruby_version]).to eq(ruby_version)
        expect(status[:provisioned]).to be true
        expect(status[:running]).to be true
        expect(status[:status_icon]).to eq("✅")
        expect(status[:health_status]).to eq(:healthy)
        expect(status[:health_icon]).to eq("💚")
        expect(status[:resources]).to have_key(:memory)
        expect(status[:resources]).to have_key(:cpu)
      end

      it "includes container details" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:container_id]).to eq("abc123")
        expect(status[:volume_name]).to eq("gemdock-ruby-3_2_0")
        expect(status[:container_name]).to eq("gemdock-ruby-3_2_0")
      end

      it "includes timestamps" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:last_used]).to eq("2024-10-22 10:00:00")
        expect(status[:created_at]).to eq("2024-10-20 15:30:00")
      end
    end

    context "with stopped container" do
      before do
        allow(state_manager).to receive(:container_provisioned?).with(ruby_version).and_return(true)
        allow(lifecycle).to receive(:running?).with(ruby_version).and_return(false)
      end

      it "returns status without health or resources" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:running]).to be false
        expect(status[:status_icon]).to eq("⏸️")
        expect(status[:health_status]).to be_nil
        expect(status[:resources]).to be_nil
      end

      it "includes basic container info" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:container_id]).to eq("abc123")
        expect(status[:volume_name]).to eq("gemdock-ruby-3_2_0")
      end
    end

    context "with not provisioned container" do
      before do
        allow(state_manager).to receive(:container_provisioned?).with(ruby_version).and_return(false)
        allow(lifecycle).to receive(:running?).with(ruby_version).and_return(false)
      end

      it "returns minimal status" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:provisioned]).to be false
        expect(status[:running]).to be false
        expect(status[:status_icon]).to eq("❌")
      end
    end

    context "with unhealthy container" do
      let(:health_status) do
        GemDock::ContainerHealthCheck::HealthStatus.new(
          status: :unhealthy,
          ruby_version: ruby_version,
          message: "Connection failed",
          checked_at: Time.now
        )
      end

      before do
        allow(state_manager).to receive(:container_provisioned?).with(ruby_version).and_return(true)
        allow(lifecycle).to receive(:running?).with(ruby_version).and_return(true)
        allow(health_check).to receive(:check).and_return(health_status)
        allow(docker_command).to receive(:execute).with(
          "stats --no-stream --format \"{{.MemUsage}}|{{.CPUPerc}}\" gemdock-ruby-3_2_0",
          timeout: 5
        ).and_return({
          exit_code: 0,
          stdout: "50MiB / 1GiB|2.1%\n",
          stderr: ""
        })
      end

      it "returns unhealthy status" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:health_status]).to eq(:unhealthy)
        expect(status[:health_icon]).to eq("💔")
        expect(status[:health_message]).to eq("Connection failed")
      end
    end

    context "when resource stats fail" do
      before do
        allow(state_manager).to receive(:container_provisioned?).with(ruby_version).and_return(true)
        allow(lifecycle).to receive(:running?).with(ruby_version).and_return(true)
        allow(health_check).to receive(:check).and_return(
          GemDock::ContainerHealthCheck::HealthStatus.new(
            status: :healthy,
            ruby_version: ruby_version,
            message: "OK",
            checked_at: Time.now
          )
        )
        allow(docker_command).to receive(:execute).and_return({
          exit_code: 1,
          stdout: "",
          stderr: "error"
        })
      end

      it "returns empty resources hash" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:resources]).to eq({})
      end
    end

    context "when inspection fails" do
      before do
        allow(state_manager).to receive(:container_state).and_raise(StandardError.new("State error"))
      end

      it "returns error status" do
        status = inspector.inspect_container(ruby_version)

        expect(status[:provisioned]).to be false
        expect(status[:running]).to be false
        expect(status[:error]).to eq("State error")
      end

      it "logs the error" do
        expect(logger).to receive(:error).with(
          "Error inspecting container",
          hash_including(ruby_version: ruby_version, error: "State error")
        )

        inspector.inspect_container(ruby_version)
      end
    end
  end

  describe "#inspect_all_containers" do
    let(:containers) do
      {
        "3.2.0" => { "status" => "running" },
        "3.1.0" => { "status" => "stopped" },
        "3.0.0" => { "status" => "stopped" }
      }
    end

    before do
      allow(state_manager).to receive(:all_containers).and_return(containers)
      allow(inspector).to receive(:inspect_container).and_call_original
      
      # Mock each container inspection
      containers.keys.each do |version|
        allow(state_manager).to receive(:container_state).with(version).and_return({})
        allow(state_manager).to receive(:container_provisioned?).with(version).and_return(true)
        running = version == "3.2.0"
        allow(lifecycle).to receive(:running?).with(version).and_return(running)
        
        # Mock health check for running container
        if running
          container_name = "gemdock-ruby-#{version.tr('.', '_')}"
          allow(health_check).to receive(:check).with(container_name, use_cache: false).and_return(
            GemDock::ContainerHealthCheck::HealthStatus.new(
              status: :healthy,
              ruby_version: version,
              message: "OK",
              checked_at: Time.now
            )
          )
          allow(docker_command).to receive(:execute).with(
            "stats --no-stream --format \"{{.MemUsage}}|{{.CPUPerc}}\" #{container_name}",
            timeout: 5
          ).and_return({
            exit_code: 0,
            stdout: "100MiB / 2GiB|5.5%\n",
            stderr: ""
          })
        end
      end
    end

    it "returns status for all containers" do
      results = inspector.inspect_all_containers

      expect(results).to be_an(Array)
      expect(results.size).to eq(3)
    end

    it "sorts results by version" do
      results = inspector.inspect_all_containers
      versions = results.map { |r| r[:ruby_version] }

      expect(versions).to eq(["3.0.0", "3.1.0", "3.2.0"])
    end

    it "inspects each container" do
      containers.keys.each do |version|
        expect(inspector).to receive(:inspect_container).with(version)
      end

      inspector.inspect_all_containers
    end
  end

  describe "#project_status" do
    let(:current_ruby) { "3.2.0" }
    let(:containers) do
      {
        "3.2.0" => {},
        "3.1.0" => {}
      }
    end

    before do
      allow(state_manager).to receive(:state).and_return({ "current_ruby" => current_ruby })
      allow(state_manager).to receive(:all_containers).and_return(containers)
      allow(docker_command).to receive(:docker_available?).and_return(true)
      allow(docker_command).to receive(:compose_available?).and_return(true)
      allow(lifecycle).to receive(:running?).and_return(false)
      allow(lifecycle).to receive(:running?).with("3.2.0").and_return(true)
    end

    it "returns project status" do
      allow(inspector).to receive(:inspect_container).and_return({
        ruby_version: current_ruby,
        running: true
      })

      status = inspector.project_status

      expect(status[:current_ruby_version]).to eq(current_ruby)
      expect(status[:docker_available]).to be true
      expect(status[:compose_available]).to be true
      expect(status[:total_containers]).to eq(2)
      expect(status[:running_containers]).to eq(1)
    end

    it "includes current container status" do
      container_status = { ruby_version: current_ruby, running: true }
      allow(inspector).to receive(:inspect_container).with(current_ruby).and_return(container_status)

      status = inspector.project_status

      expect(status[:current_container_status]).to eq(container_status)
    end

    context "when no current ruby version set" do
      before do
        allow(state_manager).to receive(:state).and_return({})
      end

      it "returns nil for current container status" do
        status = inspector.project_status

        expect(status[:current_ruby_version]).to be_nil
        expect(status[:current_container_status]).to be_nil
      end
    end

    context "when Docker is not available" do
      before do
        allow(docker_command).to receive(:docker_available?).and_return(false)
        allow(docker_command).to receive(:compose_available?).and_return(false)
      end

      it "reports unavailable status" do
        allow(inspector).to receive(:inspect_container).and_return({})

        status = inspector.project_status

        expect(status[:docker_available]).to be false
        expect(status[:compose_available]).to be false
      end
    end
  end

  describe "#format_container_info" do
    context "with running container" do
      let(:status) do
        {
          ruby_version: "3.2.0",
          status_icon: "✅",
          running: true,
          health_icon: "💚",
          health_status: :healthy,
          container_id: "abc123",
          resources: { memory: "100MiB / 2GiB", cpu: "5.5" },
          last_used: "2024-10-22 10:00:00",
          volume_name: "gemdock-ruby-3_2_0"
        }
      end

      it "formats complete information" do
        output = inspector.format_container_info(status)

        expect(output).to include("✅ Ruby 3.2.0")
        expect(output).to include("Status: Running 💚")
        expect(output).to include("Health: healthy")
        expect(output).to include("Container: abc123")
        expect(output).to include("Memory: 100MiB / 2GiB")
        expect(output).to include("CPU: 5.5%")
        expect(output).to include("Volume: gemdock-ruby-3_2_0")
      end
    end

    context "with stopped container" do
      let(:status) do
        {
          ruby_version: "3.1.0",
          status_icon: "⏸️",
          running: false,
          provisioned: true,
          container_id: "def456",
          last_used: "2024-10-20 08:30:00",
          volume_name: "gemdock-ruby-3_1_0"
        }
      end

      it "formats stopped container info" do
        output = inspector.format_container_info(status)

        expect(output).to include("⏸️ Ruby 3.1.0")
        expect(output).to include("Status: Stopped")
        expect(output).to include("Container: def456")
        expect(output).not_to include("Health:")
        expect(output).not_to include("Memory:")
      end
    end

    context "with not provisioned container" do
      let(:status) do
        {
          ruby_version: "3.0.0",
          status_icon: "❌",
          running: false,
          provisioned: false
        }
      end

      it "formats minimal info" do
        output = inspector.format_container_info(status)

        expect(output).to include("❌ Ruby 3.0.0")
        expect(output).to include("Status: Not Provisioned")
        expect(output).not_to include("Container:")
        expect(output).not_to include("Volume:")
      end
    end
  end

  describe "#format_project_status" do
    let(:status) do
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
        total_containers: 3,
        running_containers: 1
      }
    end

    it "formats project status" do
      output = inspector.format_project_status(status)

      expect(output).to include("Project Status")
      expect(output).to include("Current Ruby: 3.2.0")
      expect(output).to include("Container Status: Running ✅")
      expect(output).to include("Health: healthy 💚")
      expect(output).to include("Docker: ✅ Available")
      expect(output).to include("Docker Compose: ✅ Available")
      expect(output).to include("Total: 3")
      expect(output).to include("Running: 1")
    end

    context "with no current version" do
      let(:status) do
        {
          current_ruby_version: nil,
          current_container_status: nil,
          docker_available: true,
          compose_available: true,
          total_containers: 0,
          running_containers: 0
        }
      end

      it "shows not set message" do
        output = inspector.format_project_status(status)

        expect(output).to include("Current Ruby: Not set")
      end
    end
  end
end
