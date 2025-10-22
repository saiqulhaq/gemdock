# frozen_string_literal: true

require "spec_helper"
require "gem_dock/cli"

RSpec.describe GemDock::Config do
  let(:config_manager) { instance_double(GemDock::ConfigManager) }
  let(:config) { GemDock::Config.new }

  before do
    allow(GemDock::ConfigManager).to receive(:new).and_return(config_manager)
    
    # Suppress output during tests
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdin).to receive(:gets).and_return("yes\n")
  end

  describe "#list" do
    let(:all_config) do
      {
        "mode" => "persistent",
        "auto_provision" => true,
        "auto_cleanup_idle" => false,
        "idle_timeout_hours" => 24,
        "default_ruby_version" => "3.2.0",
        "log_level" => "info"
      }
    end

    before do
      allow(config_manager).to receive(:all).and_return(all_config)
      allow(config_manager).to receive(:config_file_path).and_return("/path/to/config.yml")
    end

    it "displays all configuration settings" do
      expect($stdout).to receive(:puts).with("Current Configuration:")
      expect($stdout).to receive(:puts).with("Configuration file: /path/to/config.yml")

      config.invoke(:list)
    end

    it "shows each config key and value" do
      all_config.each do |key, value|
        expect($stdout).to receive(:puts).with(/#{key}: #{value}/)
      end

      config.invoke(:list)
    end

    context "with nil values" do
      let(:all_config) do
        {
          "mode" => "persistent",
          "default_ruby_version" => nil
        }
      end

      it "displays '(not set)' for nil values" do
        expect($stdout).to receive(:puts).with(/default_ruby_version: \(not set\)/)

        config.invoke(:list)
      end
    end

    context "when error occurs" do
      before do
        allow(config_manager).to receive(:all).and_raise(StandardError.new("File error"))
      end

      it "displays error and exits" do
        expect { config.invoke(:list) }.to raise_error(SystemExit)
      end
    end
  end

  describe "#get" do
    before do
      allow(config_manager).to receive(:valid_keys).and_return(
        ["mode", "auto_provision", "default_ruby_version"]
      )
    end

    context "with valid key" do
      it "displays the value" do
        allow(config_manager).to receive(:key_exists?).with("mode").and_return(true)
        allow(config_manager).to receive(:get).with("mode").and_return("persistent")

        expect($stdout).to receive(:puts).with("mode: persistent")

        config.invoke(:get, ["mode"])
      end

      it "displays '(not set)' for nil value" do
        allow(config_manager).to receive(:key_exists?).with("default_ruby_version").and_return(true)
        allow(config_manager).to receive(:get).with("default_ruby_version").and_return(nil)

        expect($stdout).to receive(:puts).with("default_ruby_version: (not set)")

        config.invoke(:get, ["default_ruby_version"])
      end
    end

    context "with invalid key" do
      it "displays error and exits" do
        allow(config_manager).to receive(:key_exists?).with("invalid_key").and_return(false)

        expect($stdout).to receive(:puts).with(/Error: Unknown configuration key/)
        expect { config.invoke(:get, ["invalid_key"]) }.to raise_error(SystemExit)
      end

      it "shows valid keys" do
        allow(config_manager).to receive(:key_exists?).with("invalid_key").and_return(false)

        expect($stdout).to receive(:puts).with(/Valid keys:/)
        expect { config.invoke(:get, ["invalid_key"]) }.to raise_error(SystemExit)
      end
    end
  end

  describe "#set" do
    before do
      allow(config_manager).to receive(:config_file_path).and_return("/path/to/config.yml")
      allow(config_manager).to receive(:key_exists?).and_return(true)
    end

    context "with string value" do
      it "sets the configuration" do
        expect(config_manager).to receive(:set).with("mode", "ephemeral")
        expect($stdout).to receive(:puts).with("Configuration updated: mode = ephemeral")

        config.invoke(:set, ["mode", "ephemeral"])
      end
    end

    context "with boolean values" do
      it "converts 'true' to boolean true" do
        expect(config_manager).to receive(:set).with("auto_provision", true)

        config.invoke(:set, ["auto_provision", "true"])
      end

      it "converts 'yes' to boolean true" do
        expect(config_manager).to receive(:set).with("auto_provision", true)

        config.invoke(:set, ["auto_provision", "yes"])
      end

      it "converts '1' to boolean true" do
        expect(config_manager).to receive(:set).with("auto_provision", true)

        config.invoke(:set, ["auto_provision", "1"])
      end

      it "converts 'false' to boolean false" do
        expect(config_manager).to receive(:set).with("auto_provision", false)

        config.invoke(:set, ["auto_provision", "false"])
      end

      it "converts 'no' to boolean false" do
        expect(config_manager).to receive(:set).with("auto_cleanup_idle", false)

        config.invoke(:set, ["auto_cleanup_idle", "no"])
      end

      it "handles invalid boolean values" do
        expect($stdout).to receive(:puts).with(/Error.*Invalid boolean value/)
        expect { config.invoke(:set, ["auto_provision", "maybe"]) }.to raise_error(SystemExit)
      end
    end

    context "with integer values" do
      it "converts to integer" do
        expect(config_manager).to receive(:set).with("idle_timeout_hours", 48)

        config.invoke(:set, ["idle_timeout_hours", "48"])
      end

      it "handles invalid integer values" do
        expect($stdout).to receive(:puts).with(/Error.*Invalid integer value/)
        expect { config.invoke(:set, ["idle_timeout_hours", "abc"]) }.to raise_error(SystemExit)
      end
    end

    context "with validation error" do
      it "displays error message and suggestion" do
        error = GemDock::Validators::ValidationError.new(
          "Invalid mode",
          field: "mode",
          value: "invalid",
          suggestion: "Use: persistent or ephemeral"
        )
        allow(config_manager).to receive(:set).and_raise(error)

        expect($stdout).to receive(:puts).with(/Error.*Invalid mode.*persistent or ephemeral/m)
        expect { config.invoke(:set, ["mode", "invalid"]) }.to raise_error(SystemExit)
      end
    end

    context "when error occurs" do
      it "displays error and exits" do
        allow(config_manager).to receive(:set).and_raise(StandardError.new("Write error"))

        expect($stdout).to receive(:puts).with(/Error setting configuration/)
        expect { config.invoke(:set, ["mode", "persistent"]) }.to raise_error(SystemExit)
      end
    end
  end

  describe "#reset" do
    before do
      allow(config_manager).to receive(:config_file_path).and_return("/path/to/config.yml")
    end

    context "without force flag" do
      it "asks for confirmation" do
        allow(config_manager).to receive(:reset!)
        allow(GemDock::PromptHelper).to receive(:yes_no).and_return(true)
        
        expect { config.invoke(:reset) }.to output(/Configuration reset to defaults/).to_stdout
      end

      it "resets when user confirms" do
        allow(GemDock::PromptHelper).to receive(:yes_no).and_return(true)
        
        expect(config_manager).to receive(:reset!)

        expect { config.invoke(:reset) }.to output(/Configuration reset to defaults/).to_stdout
      end

      it "cancels when user declines" do
        allow(GemDock::PromptHelper).to receive(:yes_no).and_return(false)
        
        expect(config_manager).not_to receive(:reset!)

        expect { config.invoke(:reset) }.to output(/Reset cancelled/).to_stdout
      end
    end

    context "with force flag" do
      it "skips confirmation" do
        expect(GemDock::PromptHelper).not_to receive(:yes_no)
        expect(config_manager).to receive(:reset!)

        config.invoke(:reset, [], force: true)
      end

      it "resets configuration" do
        expect(config_manager).to receive(:reset!)
        expect($stdout).to receive(:puts).with("Configuration reset to defaults.")

        config.invoke(:reset, [], force: true)
      end
    end

    context "when error occurs" do
      it "displays error and exits" do
        allow(config_manager).to receive(:reset!).and_raise(StandardError.new("Write error"))

        expect($stdout).to receive(:puts).with(/Error resetting configuration/)
        expect { config.invoke(:reset, [], force: true) }.to raise_error(SystemExit)
      end
    end
  end
end
