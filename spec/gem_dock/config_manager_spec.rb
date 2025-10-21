require "spec_helper"
require "gem_dock/config_manager"
require "fakefs/spec_helpers"

RSpec.describe GemDock::ConfigManager do
  let(:config_dir) { GemDock::ConfigManager::CONFIG_DIR }
  let(:config_file) { GemDock::ConfigManager::CONFIG_FILE }

  around do |example|
    FileUtils.mkdir_p(config_dir)
    example.run
    FileUtils.rm_rf(config_dir)
  end

  describe "#initialize" do
    context "when config file does not exist" do
      it "creates the config file with default values" do
        described_class.new
        expect(File.exist?(config_file)).to be true
        config = YAML.safe_load(File.read(config_file))
        expect(config).to eq(GemDock::ConfigManager::DEFAULT_CONFIG)
      end
    end

    context "when config file is empty" do
      before { FileUtils.touch(config_file) }

      it "loads default configuration" do
        manager = described_class.new
        expect(manager.config).to eq(GemDock::ConfigManager::DEFAULT_CONFIG)
      end
    end

    context "when config file is corrupted" do
      before { File.write(config_file, "invalid: yaml:") }

      it "loads default configuration" do
        manager = described_class.new
        expect(manager.config).to eq(GemDock::ConfigManager::DEFAULT_CONFIG)
      end
    end

    context "when config file has partial settings" do
      let(:user_config) { {"mode" => "ephemeral", "log_level" => "debug"} }
      before { File.write(config_file, YAML.dump(user_config)) }

      it "merges user config with defaults" do
        manager = described_class.new
        expect(manager.get("mode")).to eq("ephemeral")
        expect(manager.get("log_level")).to eq("debug")
        expect(manager.get("auto_provision")).to be true # from default
      end
    end
  end

  describe "#set" do
    subject(:manager) { described_class.new }

    it "updates a valid configuration value" do
      manager.set("mode", "ephemeral")
      expect(manager.get("mode")).to eq("ephemeral")
    end

    it "persists the change to the config file" do
      manager.set("log_level", "warn")
      new_manager = described_class.new
      expect(new_manager.get("log_level")).to eq("warn")
    end

    it "performs an atomic save" do
      expect(File).to receive(:rename).with(/#{Regexp.escape(config_file)}\.tmp\.\d+/, config_file).and_call_original
      manager.set("mode", "ephemeral")
    end

    context "with invalid values" do
      it "raises an error for invalid mode" do
        expect { manager.set("mode", "invalid") }.to raise_error(ArgumentError, /Invalid mode/)
      end

      it "raises an error for invalid boolean" do
        expect { manager.set("auto_provision", "not_a_bool") }.to raise_error(ArgumentError, /Invalid boolean/)
      end

      it "raises an error for invalid idle timeout" do
        expect { manager.set("idle_timeout_hours", 999) }.to raise_error(ArgumentError, /Idle timeout must be an integer/)
      end

      it "raises an error for invalid Ruby version format" do
        expect { manager.set("default_ruby_version", "3.2") }.to raise_error(ArgumentError, /Invalid Ruby version format/)
      end

      it "raises an error for invalid log level" do
        expect { manager.set("log_level", "verbose") }.to raise_error(ArgumentError, /Invalid log level/)
      end

      it "raises an error for an unknown key" do
        expect { manager.set("new_feature_enabled", true) }.to raise_error(ArgumentError, /Unknown configuration key/)
      end
    end
  end

  describe "helper methods" do
    it "#persistent_mode? returns true when mode is persistent" do
      manager = described_class.new
      expect(manager.persistent_mode?).to be true
    end

    it "#ephemeral_mode? returns true when mode is ephemeral" do
      File.write(config_file, YAML.dump({"mode" => "ephemeral"}))
      manager = described_class.new
      expect(manager.ephemeral_mode?).to be true
    end

    it "#auto_provision? returns the value of auto_provision" do
      manager = described_class.new
      expect(manager.auto_provision?).to be true
      manager.set("auto_provision", false)
      expect(manager.auto_provision?).to be false
    end
  end
end