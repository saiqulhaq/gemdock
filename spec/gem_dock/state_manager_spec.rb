require "spec_helper"
require "gem_dock/state_manager"
require "fakefs/spec_helpers"

RSpec.describe GemDock::StateManager do
  include FakeFS::SpecHelpers

  let(:state_dir) { GemDock::StateManager::STATE_DIR }
  let(:state_file) { GemDock::StateManager::STATE_FILE }

  around do |example|
    FakeFS.with_fresh do
      FileUtils.mkdir_p(Dir.pwd)
      example.run
    end
  end

  describe "#initialize" do
    context "when state file does not exist" do
      it "creates the state file with default values" do
        manager = described_class.new
        expect(File.exist?(state_file)).to be true
        state = YAML.safe_load(File.read(state_file))
        expect(state["version"]).to eq(GemDock::StateManager::STATE_VERSION)
        expect(state["containers"]).to eq({})
      end
    end

    context "when state file is corrupted" do
      before do
        FileUtils.mkdir_p(state_dir)
        File.write(state_file, "invalid: yaml: content:")
      end

      it "backs up the corrupted file" do
        described_class.new
        backup_files = Dir.glob("#{state_file}.backup.*")
        expect(backup_files).not_to be_empty
      end

      it "creates a new state file with defaults" do
        manager = described_class.new
        expect(manager.state["version"]).to eq(GemDock::StateManager::STATE_VERSION)
        expect(manager.state["containers"]).to eq({})
      end
    end

    context "when state file has valid content" do
      let(:valid_state) do
        {
          "version" => "1.0.0",
          "current_ruby" => "3.2.0",
          "project_root" => Dir.pwd,
          "last_updated" => Time.now.utc.iso8601,
          "containers" => {
            "3.2.0" => {
              "container_id" => "a" * 64,
              "status" => "running",
              "last_used" => Time.now.utc.iso8601,
              "volume_name" => "bundler_data_ruby_3_2_0",
              "compose_file" => ".gemdock/docker-compose-ruby-3-2-0.yml",
              "created_at" => Time.now.utc.iso8601
            }
          }
        }
      end

      before do
        FileUtils.mkdir_p(state_dir)
        File.write(state_file, YAML.dump(valid_state))
      end

      it "loads the existing state" do
        manager = described_class.new
        expect(manager.state["current_ruby"]).to eq("3.2.0")
        expect(manager.state["containers"]["3.2.0"]["status"]).to eq("running")
      end
    end
  end

  describe "#container_state" do
    subject(:manager) { described_class.new }

    context "when container exists" do
      before do
        manager.update_container("3.2.0", {
          "container_id" => "a" * 64,
          "status" => "running"
        })
      end

      it "returns the container state" do
        state = manager.container_state("3.2.0")
        expect(state["status"]).to eq("running")
        expect(state["container_id"]).to eq("a" * 64)
      end
    end

    context "when container does not exist" do
      it "returns default container state" do
        state = manager.container_state("3.2.0")
        expect(state["status"]).to eq("not_provisioned")
        expect(state["container_id"]).to be_nil
      end
    end
  end

  describe "#update_container" do
    subject(:manager) { described_class.new }

    it "updates container state" do
      manager.update_container("3.2.0", {
        "container_id" => "b" * 64,
        "status" => "running"
      })
      
      state = manager.container_state("3.2.0")
      expect(state["status"]).to eq("running")
      expect(state["container_id"]).to eq("b" * 64)
    end

    it "persists changes to state file" do
      # First transition to running
      manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
      # Then transition to stopped
      manager.update_container("3.2.0", {"status" => "stopped"})
      
      new_manager = described_class.new
      expect(new_manager.container_state("3.2.0")["status"]).to eq("stopped")
    end

    it "updates last_updated timestamp" do
      before_time = Time.now.utc - 1 # 1 second before to avoid timing issues
      manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
      
      last_updated = Time.parse(manager.state["last_updated"])
      expect(last_updated).to be >= before_time
    end

    it "performs atomic save" do
      expect(File).to receive(:rename).with(/#{Regexp.escape(state_file)}\.tmp\.\d+/, state_file).and_call_original
      manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
    end
  end

  describe "#set_current_ruby" do
    subject(:manager) { described_class.new }

    it "sets the current Ruby version" do
      manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
      manager.set_current_ruby("3.2.0")
      expect(manager.current_ruby).to eq("3.2.0")
    end

    it "persists the change" do
      manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
      manager.set_current_ruby("3.2.0")
      new_manager = described_class.new
      expect(new_manager.current_ruby).to eq("3.2.0")
    end
  end

  describe "status check methods" do
    subject(:manager) { described_class.new }

    describe "#container_running?" do
      before do
        manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
        # Setup 3.1.0 - first to running, then to stopped
        manager.update_container("3.1.0", {"status" => "running", "container_id" => "b" * 64})
        manager.update_container("3.1.0", {"status" => "stopped"})
      end

      it "returns true for running containers" do
        expect(manager.container_running?("3.2.0")).to be true
      end

      it "returns false for non-running containers" do
        expect(manager.container_running?("3.1.0")).to be false
      end
    end

    describe "#container_stopped?" do
      before do
        # Setup a container in stopped state
        manager.update_container("3.1.0", {"status" => "running", "container_id" => "b" * 64})
        manager.update_container("3.1.0", {"status" => "stopped"})
        # Setup another in running state
        manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
      end

      it "returns true for stopped containers" do
        expect(manager.container_stopped?("3.1.0")).to be true
      end

      it "returns false for non-stopped containers" do
        expect(manager.container_stopped?("3.2.0")).to be false
      end
    end

    describe "#container_provisioned?" do
      before do
        manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
        # Setup 3.1.0 in stopped state (still provisioned)
        manager.update_container("3.1.0", {"status" => "running", "container_id" => "b" * 64})
        manager.update_container("3.1.0", {"status" => "stopped"})
      end

      it "returns true for provisioned containers" do
        expect(manager.container_provisioned?("3.2.0")).to be true
        expect(manager.container_provisioned?("3.1.0")).to be true
      end

      it "returns false for not provisioned containers" do
        expect(manager.container_provisioned?("2.7.0")).to be false
      end
    end
  end

  describe "#all_containers" do
    subject(:manager) { described_class.new }

    it "returns all containers" do
      manager.update_container("3.2.0", {"status" => "running", "container_id" => "a" * 64})
      # Setup 3.1.0 - first to running, then to stopped
      manager.update_container("3.1.0", {"status" => "running", "container_id" => "b" * 64})
      manager.update_container("3.1.0", {"status" => "stopped"})
      
      containers = manager.all_containers
      expect(containers.keys).to contain_exactly("3.2.0", "3.1.0")
    end
  end

  describe "state validation" do
    context "with invalid status" do
      let(:invalid_state) do
        {
          "version" => "1.0.0",
          "containers" => {
            "3.2.0" => {
              "status" => "invalid_status",
              "container_id" => nil
            }
          }
        }
      end

      before do
        FileUtils.mkdir_p(state_dir)
        File.write(state_file, YAML.dump(invalid_state))
      end

      it "handles invalid state and creates default" do
        manager = described_class.new
        expect(manager.state["containers"]).to eq({})
      end
    end

    context "with invalid container_id format" do
      let(:invalid_state) do
        {
          "version" => "1.0.0",
          "containers" => {
            "3.2.0" => {
              "status" => "running",
              "container_id" => "invalid"
            }
          }
        }
      end

      before do
        FileUtils.mkdir_p(state_dir)
        File.write(state_file, YAML.dump(invalid_state))
      end

      it "handles invalid container_id and creates default" do
        manager = described_class.new
        expect(manager.state["containers"]).to eq({})
      end
    end

    context "with not_provisioned status but has container_id" do
      let(:invalid_state) do
        {
          "version" => "1.0.0",
          "containers" => {
            "3.2.0" => {
              "status" => "not_provisioned",
              "container_id" => "a" * 64
            }
          }
        }
      end

      before do
        FileUtils.mkdir_p(state_dir)
        File.write(state_file, YAML.dump(invalid_state))
      end

      it "handles inconsistent state and creates default" do
        manager = described_class.new
        expect(manager.state["containers"]).to eq({})
      end
    end
  end
end