# frozen_string_literal: true

require "spec_helper"
require "gem_dock/container_cleanup"
require "gem_dock/docker_command"
require "gem_dock/state_manager"
require "gem_dock/config_manager"
require "gem_dock/container_lifecycle"

RSpec.describe GemDock::ContainerCleanup do
  let(:docker_command) { instance_double(GemDock::DockerCommand) }
  let(:state_manager) { instance_double(GemDock::StateManager) }
  let(:config_manager) { instance_double(GemDock::ConfigManager) }
  let(:lifecycle) { instance_double(GemDock::ContainerLifecycle) }
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }

  let(:cleanup) do
    described_class.new(
      docker_command: docker_command,
      state_manager: state_manager,
      config_manager: config_manager,
      lifecycle: lifecycle,
      logger: logger
    )
  end

  describe "#identify_cleanup_candidates" do
    let(:containers) do
      {
        "3.2.0" => {
          "status" => "stopped",
          "last_used" => (Time.now - 48 * 3600).to_s # 48 hours ago
        },
        "3.1.0" => {
          "status" => "stopped",
          "last_used" => (Time.now - 12 * 3600).to_s # 12 hours ago
        },
        "3.0.0" => {
          "status" => "running",
          "last_used" => (Time.now - 50 * 3600).to_s # 50 hours ago but running
        }
      }
    end

    before do
      allow(state_manager).to receive(:all_containers).and_return(containers)
      allow(config_manager).to receive(:get).with("idle_timeout").and_return(24)
    end

    context "with default timeout" do
      it "identifies containers idle longer than 24 hours" do
        allow(lifecycle).to receive(:running?).with("3.2.0").and_return(false)
        allow(lifecycle).to receive(:running?).with("3.1.0").and_return(false)
        allow(lifecycle).to receive(:running?).with("3.0.0").and_return(true)

        candidates = cleanup.identify_cleanup_candidates

        expect(candidates).to include("3.2.0")
        expect(candidates).not_to include("3.1.0")
        expect(candidates).not_to include("3.0.0")
      end
    end

    context "with all flag" do
      it "includes all stopped containers regardless of age" do
        allow(lifecycle).to receive(:running?).with("3.2.0").and_return(false)
        allow(lifecycle).to receive(:running?).with("3.1.0").and_return(false)
        allow(lifecycle).to receive(:running?).with("3.0.0").and_return(true)

        candidates = cleanup.identify_cleanup_candidates(all: true)

        expect(candidates).to include("3.2.0")
        expect(candidates).to include("3.1.0")
        expect(candidates).not_to include("3.0.0")
      end
    end

    context "with running containers" do
      it "never includes running containers" do
        allow(lifecycle).to receive(:running?).and_return(true)

        candidates = cleanup.identify_cleanup_candidates(all: true)

        expect(candidates).to be_empty
      end
    end

    context "with invalid timestamps" do
      let(:containers) do
        {
          "3.2.0" => {
            "status" => "stopped",
            "last_used" => "invalid-timestamp"
          }
        }
      end

      it "skips containers with invalid timestamps" do
        allow(lifecycle).to receive(:running?).with("3.2.0").and_return(false)

        candidates = cleanup.identify_cleanup_candidates

        expect(candidates).to be_empty
      end
    end
  end

  describe "#clean_container" do
    let(:ruby_version) { "3.2.0" }
    let(:compose_file) { "/Users/test/.gemdock/docker-compose-ruby-3_2_0.yml" }

    before do
      allow(ENV).to receive(:[]).with("HOME").and_return("/Users/test")
    end

    context "when successful" do
      before do
        allow(lifecycle).to receive(:remove).with(ruby_version, remove_volume: true).and_return(true)
        allow(File).to receive(:exist?).with(compose_file).and_return(true)
        allow(File).to receive(:delete).with(compose_file)
        allow(state_manager).to receive(:update_container)
      end

      it "removes the container" do
        expect(lifecycle).to receive(:remove).with(ruby_version, remove_volume: true)

        cleanup.clean_container(ruby_version)
      end

      it "removes the compose file" do
        expect(File).to receive(:delete).with(compose_file)

        cleanup.clean_container(ruby_version)
      end

      it "updates the state" do
        expect(state_manager).to receive(:update_container).with(
          ruby_version,
          'status' => "not_provisioned",
          container_id: nil,
          volume_name: nil
        )

        cleanup.clean_container(ruby_version)
      end

      it "returns true" do
        result = cleanup.clean_container(ruby_version)

        expect(result).to be true
      end
    end

    context "when container removal fails" do
      before do
        allow(lifecycle).to receive(:remove).and_return(false)
      end

      it "returns false" do
        result = cleanup.clean_container(ruby_version)

        expect(result).to be false
      end

      it "does not update state" do
        expect(state_manager).not_to receive(:update_container)

        cleanup.clean_container(ruby_version)
      end
    end

    context "when compose file does not exist" do
      before do
        allow(lifecycle).to receive(:remove).and_return(true)
        allow(File).to receive(:exist?).with(compose_file).and_return(false)
        allow(state_manager).to receive(:update_container)
      end

      it "does not try to delete the file" do
        expect(File).not_to receive(:delete)

        cleanup.clean_container(ruby_version)
      end

      it "still updates state" do
        expect(state_manager).to receive(:update_container)

        cleanup.clean_container(ruby_version)
      end
    end

    context "with remove_volume false" do
      it "passes the flag to lifecycle" do
        allow(lifecycle).to receive(:remove).with(ruby_version, remove_volume: false).and_return(true)
        allow(File).to receive(:exist?).and_return(false)
        allow(state_manager).to receive(:update_container)

        expect(lifecycle).to receive(:remove).with(ruby_version, remove_volume: false)

        cleanup.clean_container(ruby_version, remove_volume: false)
      end
    end
  end

  describe "#cleanup" do
    let(:candidates) { ["3.2.0", "3.1.0"] }

    before do
      allow(cleanup).to receive(:identify_cleanup_candidates).and_return(candidates)
    end

    context "with no candidates" do
      let(:candidates) { [] }

      it "returns zero counts" do
        result = cleanup.cleanup

        expect(result).to eq(cleaned: 0, skipped: 0, failed: 0)
      end
    end

    context "with dry_run flag" do
      before do
        allow(state_manager).to receive(:container_state).and_return({
          "last_used" => "2024-01-01",
          "volume_name" => "gemdock-ruby-3-2-0"
        })
      end

      it "does not perform cleanup" do
        expect(cleanup).not_to receive(:clean_container)

        cleanup.cleanup(dry_run: true)
      end

      it "reports what would be cleaned" do
        result = cleanup.cleanup(dry_run: true)

        expect(result).to include(
          cleaned: 0,
          skipped: 2,
          failed: 0,
          dry_run: true
        )
      end
    end

    context "without force flag" do
      before do
        allow(cleanup).to receive(:confirm_cleanup).and_return(false)
      end

      it "asks for confirmation" do
        expect(cleanup).to receive(:confirm_cleanup).with(candidates)

        cleanup.cleanup
      end

      it "skips cleanup if not confirmed" do
        expect(cleanup).not_to receive(:clean_container)

        result = cleanup.cleanup

        expect(result).to eq(cleaned: 0, skipped: 2, failed: 0)
      end
    end

    context "with force flag" do
      before do
        allow(cleanup).to receive(:clean_container).and_return(true)
      end

      it "does not ask for confirmation" do
        expect(cleanup).not_to receive(:confirm_cleanup)

        cleanup.cleanup(force: true)
      end

      it "performs cleanup" do
        expect(cleanup).to receive(:clean_container).with("3.2.0", remove_volume: true)
        expect(cleanup).to receive(:clean_container).with("3.1.0", remove_volume: true)

        cleanup.cleanup(force: true)
      end
    end

    context "with mixed results" do
      before do
        allow(cleanup).to receive(:confirm_cleanup).and_return(true)
        allow(cleanup).to receive(:clean_container).with("3.2.0", remove_volume: true).and_return(true)
        allow(cleanup).to receive(:clean_container).with("3.1.0", remove_volume: true).and_return(false)
      end

      it "counts successes and failures" do
        result = cleanup.cleanup

        expect(result).to eq(cleaned: 1, skipped: 0, failed: 1)
      end
    end
  end

  describe "#cleanup_stats" do
    let(:all_containers) do
      {
        "3.2.0" => { "status" => "stopped", "last_used" => (Time.now - 48 * 3600).to_s },
        "3.1.0" => { "status" => "stopped", "last_used" => (Time.now - 12 * 3600).to_s },
        "3.0.0" => { "status" => "running", "last_used" => Time.now.to_s }
      }
    end

    before do
      allow(state_manager).to receive(:all_containers).and_return(all_containers)
      allow(config_manager).to receive(:get).with("idle_timeout").and_return(24)
      allow(lifecycle).to receive(:running?).with("3.2.0").and_return(false)
      allow(lifecycle).to receive(:running?).with("3.1.0").and_return(false)
      allow(lifecycle).to receive(:running?).with("3.0.0").and_return(true)
    end

    it "returns statistics about containers" do
      stats = cleanup.cleanup_stats

      expect(stats[:total_containers]).to eq(3)
      expect(stats[:running_containers]).to eq(1)
      expect(stats[:stopped_containers]).to eq(2)
      expect(stats[:idle_containers]).to eq(1)
      expect(stats[:idle_timeout_hours]).to eq(24)
    end
  end
end
