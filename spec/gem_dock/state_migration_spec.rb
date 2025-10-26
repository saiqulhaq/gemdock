require "spec_helper"
require "gem_dock/state_migration"
require "gem_dock/logger"
require "tmpdir"

RSpec.describe GemDock::StateMigration do
  let(:tmpdir) { Dir.mktmpdir }
  let(:state_file) { File.join(tmpdir, "state.yml") }
  let(:logger) { GemDock::Logger.new }
  let(:migration) { described_class.new(logger: logger) }
  let(:log_file) { GemDock::Logger::LOG_FILE }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "#detect_version" do
    it "returns version from state with version field" do
      state = { "version" => "1.0.0" }
      expect(migration.detect_version(state)).to eq("1.0.0")
    end

    it "returns nil for legacy state without version" do
      state = { "containers" => {} }
      expect(migration.detect_version(state)).to be_nil
    end

    it "returns nil for invalid state" do
      expect(migration.detect_version(nil)).to be_nil
      expect(migration.detect_version("invalid")).to be_nil
    end
  end

  describe "#migration_needed?" do
    it "returns true for legacy state" do
      state = { "containers" => {} }
      expect(migration.migration_needed?(state)).to be true
    end

    it "returns false for current version" do
      state = { "version" => described_class::CURRENT_VERSION }
      expect(migration.migration_needed?(state)).to be false
    end

    it "returns true for different version" do
      state = { "version" => "0.9.0" }
      expect(migration.migration_needed?(state)).to be true
    end
  end

  describe "#migrate" do
    context "when state file does not exist" do
      it "returns default state" do
        result = migration.migrate(state_file)
        
        expect(result).to include(
          "version" => described_class::CURRENT_VERSION,
          "current_ruby" => nil,
          "containers" => {},
          "last_updated" => kind_of(String)
        )
      end
    end

    context "with legacy state format" do
      let(:legacy_state) do
        {
          "current_ruby" => "3.2.0",
          "containers" => {
            "3.2.0" => {
              "status" => "running",
              "container_id" => "abc123",
              "last_used" => "2025-10-22T14:00:00Z"
            }
          }
        }
      end

      before do
        File.write(state_file, legacy_state.to_yaml)
      end

      it "migrates to v1.0.0 format" do
        result = migration.migrate(state_file)
        
        expect(result["version"]).to eq("1.0.0")
        expect(result["current_ruby"]).to eq("3.2.0")
        expect(result["containers"]["3.2.0"]).to include(
          "status" => "running",
          "container_id" => "abc123",
          "volume_name" => "bundler_data_ruby_3_2_0",
          "last_used" => "2025-10-22T14:00:00Z"
        )
      end

      it "creates a backup file" do
        migration.migrate(state_file)
        
        backup_files = Dir.glob("#{state_file}.backup.*")
        expect(backup_files).not_to be_empty
      end

      it "logs migration operations" do
        migration.migrate(state_file)
        
        log_content = File.read(log_file)
        expect(log_content).to include("Detected legacy state format")
        expect(log_content).to include("Successfully migrated state to v1.0.0")
      end
    end

    context "with current version state" do
      let(:current_state) do
        {
          "version" => "1.0.0",
          "current_ruby" => "3.2.0",
          "containers" => {},
          "last_updated" => "2025-10-22T14:00:00Z"
        }
      end

      before do
        File.write(state_file, current_state.to_yaml)
      end

      it "returns state unchanged" do
        result = migration.migrate(state_file)
        
        expect(result["version"]).to eq("1.0.0")
        expect(result["current_ruby"]).to eq("3.2.0")
      end

      it "does not create backup" do
        migration.migrate(state_file)
        
        backup_files = Dir.glob("#{state_file}.backup.*")
        expect(backup_files).to be_empty
      end
    end

    context "with unsupported version" do
      let(:future_state) do
        {
          "version" => "2.0.0",
          "containers" => {}
        }
      end

      before do
        File.write(state_file, future_state.to_yaml)
      end

      it "raises UnsupportedVersionError" do
        expect { migration.migrate(state_file) }.to raise_error(
          GemDock::StateMigration::UnsupportedVersionError,
          /Unsupported state file version: 2.0.0/
        )
      end

      it "logs error message" do
        begin
          migration.migrate(state_file)
        rescue GemDock::StateMigration::UnsupportedVersionError
          # Expected
        end

        log_content = File.read(log_file)
        expect(log_content).to include("Unsupported state file version")
      end
    end

    context "with corrupted state file" do
      before do
        File.write(state_file, "invalid: yaml: content:")
      end

      it "returns default state" do
        result = migration.migrate(state_file)
        
        expect(result["version"]).to eq("1.0.0")
        expect(result["containers"]).to eq({})
      end

      it "logs error" do
        migration.migrate(state_file)
        
        log_content = File.read(log_file)
        expect(log_content).to include("Failed to parse state file")
      end
    end
  end

  describe "legacy container migration" do
    let(:legacy_state) do
      {
        "containers" => {
          "3.2.0" => {
            "status" => "running",
            "container_id" => "abc123"
            # Missing: volume_name, last_used, last_updated
          },
          "3.1.0" => {
            "status" => "stopped",
            "container_id" => nil,
            "last_used" => "2025-10-20T10:00:00Z"
            # Missing: volume_name, last_updated
          }
        }
      }
    end

    before do
      File.write(state_file, legacy_state.to_yaml)
    end

    it "adds missing volume_name field" do
      result = migration.migrate(state_file)
      
      expect(result["containers"]["3.2.0"]["volume_name"]).to eq("bundler_data_ruby_3_2_0")
      expect(result["containers"]["3.1.0"]["volume_name"]).to eq("bundler_data_ruby_3_1_0")
    end

    it "adds missing last_used field with current timestamp" do
      result = migration.migrate(state_file)
      
      expect(result["containers"]["3.2.0"]["last_used"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      expect(result["containers"]["3.1.0"]["last_used"]).to eq("2025-10-20T10:00:00Z")
    end

    it "adds missing last_updated field" do
      result = migration.migrate(state_file)
      
      expect(result["containers"]["3.2.0"]["last_updated"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      expect(result["containers"]["3.1.0"]["last_updated"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
    end

    it "preserves existing container data" do
      result = migration.migrate(state_file)
      
      expect(result["containers"]["3.2.0"]["status"]).to eq("running")
      expect(result["containers"]["3.2.0"]["container_id"]).to eq("abc123")
      expect(result["containers"]["3.1.0"]["status"]).to eq("stopped")
      expect(result["containers"]["3.1.0"]["container_id"]).to be_nil
    end
  end

  describe "edge cases" do
    it "handles empty containers hash" do
      state = { "containers" => {} }
      File.write(state_file, state.to_yaml)
      
      result = migration.migrate(state_file)
      expect(result["containers"]).to eq({})
    end

    it "handles missing containers key" do
      state = { "current_ruby" => "3.2.0" }
      File.write(state_file, state.to_yaml)
      
      result = migration.migrate(state_file)
      expect(result["containers"]).to eq({})
    end

    it "handles nil current_ruby" do
      state = { "current_ruby" => nil, "containers" => {} }
      File.write(state_file, state.to_yaml)
      
      result = migration.migrate(state_file)
      expect(result["current_ruby"]).to be_nil
    end
  end
end
