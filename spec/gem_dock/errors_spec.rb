# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/gem_dock/errors"

RSpec.describe GemDock::Error do
  describe "#full_message" do
    it "includes the base message" do
      error = described_class.new("Something went wrong")
      expect(error.full_message).to include("Something went wrong")
    end

    it "includes suggestions when provided" do
      error = described_class.new(
        "Error occurred",
        suggestions: ["Try this", "Or this"]
      )
      
      expect(error.full_message).to include("Suggestions:")
      expect(error.full_message).to include("• Try this")
      expect(error.full_message).to include("• Or this")
    end

    it "includes details when provided" do
      error = described_class.new(
        "Error occurred",
        details: { key: "value", count: 42 }
      )
      
      expect(error.full_message).to include("Details:")
      expect(error.full_message).to include("key: value")
      expect(error.full_message).to include("count: 42")
    end

    it "works with empty suggestions and details" do
      error = described_class.new("Simple error")
      expect(error.full_message).to eq("Simple error")
    end
  end
end

RSpec.describe GemDock::ContainerNotFoundError do
  it "provides helpful suggestions" do
    error = described_class.new("ruby-3.2.0")
    
    expect(error.message).to include("Container 'ruby-3.2.0' not found")
    expect(error.full_message).to include("gemdock provision list")
    expect(error.full_message).to include("gemdock provision create")
  end

  it "allows custom suggestions" do
    error = described_class.new("ruby-3.2.0", suggestions: ["Custom suggestion"])
    
    expect(error.full_message).to include("Custom suggestion")
    expect(error.full_message).not_to include("gemdock provision list")
  end
end

RSpec.describe GemDock::ContainerNotRunningError do
  it "provides start command suggestion" do
    error = described_class.new("ruby-3.2.0", "3.2.0")
    
    expect(error.message).to include("Container 'ruby-3.2.0' is not running")
    expect(error.full_message).to include("gemdock provision start 3.2.0")
    expect(error.full_message).to include("auto_provision")
  end

  it "works without ruby_version" do
    error = described_class.new("ruby-3.2.0")
    
    expect(error.full_message).to include("gemdock provision start")
  end
end

RSpec.describe GemDock::ContainerUnhealthyError do
  it "provides restart suggestions" do
    error = described_class.new("ruby-3.2.0", "starting")
    
    expect(error.message).to include("unhealthy")
    expect(error.message).to include("status: starting")
    expect(error.full_message).to include("gemdock provision restart")
    expect(error.details[:health_status]).to eq("starting")
  end
end

RSpec.describe GemDock::DockerNotAvailableError do
  it "provides Docker installation suggestions" do
    error = described_class.new
    
    expect(error.message).to include("Docker is not available")
    expect(error.full_message).to include("Install Docker Desktop")
    expect(error.full_message).to include("docker ps")
    expect(error.full_message).to include("docker --version")
  end
end

RSpec.describe GemDock::DockerCommandFailedError do
  it "includes command details and suggestions" do
    error = described_class.new("docker ps", 1, "permission denied")
    
    expect(error.message).to include("exit code 1")
    expect(error.details[:command]).to eq("docker ps")
    expect(error.details[:exit_code]).to eq(1)
    expect(error.details[:output]).to include("permission denied")
    expect(error.full_message).to include("Docker daemon")
  end

  it "truncates long output" do
    long_output = "a" * 300
    error = described_class.new("docker ps", 1, long_output)
    
    expect(error.details[:output].length).to be <= 200
    expect(error.details[:output].length).to eq(200) # Exactly 200 chars
  end
end

RSpec.describe GemDock::InvalidConfigError do
  it "shows valid values when provided" do
    error = described_class.new("mode", "invalid", ["persistent", "ephemeral"])
    
    expect(error.message).to include("Invalid configuration value 'invalid'")
    expect(error.full_message).to include("Valid values for 'mode': persistent, ephemeral")
    expect(error.details[:key]).to eq("mode")
    expect(error.details[:value]).to eq("invalid")
  end

  it "works without valid values list" do
    error = described_class.new("timeout", "abc")
    
    expect(error.message).to include("Invalid configuration value")
    expect(error.full_message).to include("gemdock config list")
  end
end

RSpec.describe GemDock::ConfigKeyNotFoundError do
  describe "did you mean functionality" do
    let(:available_keys) do
      ["auto_provision", "auto_cleanup_idle", "default_ruby_version", "idle_timeout_hours"]
    end

    it "suggests similar keys with substring match" do
      error = described_class.new("auto", available_keys)
      
      expect(error.message).to include("Unknown configuration key 'auto'")
      expect(error.full_message).to include("Did you mean:")
      expect(error.full_message).to match(/auto_provision|auto_cleanup_idle/)
    end

    it "suggests similar keys with typo (levenshtein distance)" do
      error = described_class.new("auto_provison", available_keys) # missing 'i'
      
      expect(error.full_message).to include("Did you mean:")
      expect(error.full_message).to include("auto_provision")
    end

    it "shows all available keys when no match found" do
      error = described_class.new("completely_wrong", available_keys)
      
      expect(error.full_message).to include("Valid keys are:")
      expect(error.full_message).to include("auto_provision")
      expect(error.full_message).to include("default_ruby_version")
    end

    it "limits suggestions to 3 keys" do
      # Use a key that will match multiple keys but limit to 3
      many_similar_keys = ["auto_provision", "auto_cleanup", "auto_start", "auto_stop", "auto_restart"]
      error = described_class.new("auto", many_similar_keys)
      suggestions_text = error.full_message
      
      # Count how many keys appear in the "Did you mean:" section only
      did_you_mean_section = suggestions_text.split("Did you mean:").last&.split("\n")&.first || ""
      suggestion_count = many_similar_keys.count { |key| did_you_mean_section.include?(key) }
      
      expect(suggestion_count).to be <= 3
    end
  end

  describe "levenshtein distance" do
    let(:available_keys) { ["test_key"] }

    it "calculates distance correctly for insertions" do
      error = described_class.new("test_ke", available_keys)
      # Distance of 1 (missing 'y')
      expect(error.full_message).to include("Did you mean:")
    end

    it "calculates distance correctly for deletions" do
      error = described_class.new("test_keyy", available_keys)
      # Distance of 1 (extra 'y')
      expect(error.full_message).to include("Did you mean:")
    end

    it "calculates distance correctly for substitutions" do
      error = described_class.new("test_kez", available_keys)
      # Distance of 1 ('z' instead of 'y')
      expect(error.full_message).to include("Did you mean:")
    end

    it "does not suggest when distance is too large" do
      error = described_class.new("xyz", available_keys)
      # Distance > 2, should not appear in "Did you mean:" section
      # But will still appear in "Valid keys are:" section
      expect(error.full_message).not_to include("Did you mean:")
      expect(error.full_message).to include("Valid keys are:")
    end
  end
end

RSpec.describe GemDock::InvalidRubyVersionError do
  it "provides version format suggestions" do
    error = described_class.new("ruby-3.2")
    
    expect(error.message).to include("Invalid Ruby version format 'ruby-3.2'")
    expect(error.full_message).to include("X.Y.Z")
    expect(error.full_message).to include("3.2.0")
    expect(error.details[:version]).to eq("ruby-3.2")
  end
end

RSpec.describe GemDock::UnsupportedRubyVersionError do
  it "provides upgrade suggestions" do
    error = described_class.new("2.5.0", "2.6.0")
    
    expect(error.message).to include("not supported")
    expect(error.message).to include("minimum: 2.6.0")
    expect(error.full_message).to include("2.6.0 or higher")
    expect(error.details[:version]).to eq("2.5.0")
    expect(error.details[:min_version]).to eq("2.6.0")
  end
end

RSpec.describe GemDock::MissingCommandError do
  it "provides help suggestions for named command" do
    error = described_class.new("provisio")
    
    expect(error.message).to include("Command 'provisio' not found")
    expect(error.full_message).to include("gemdock help")
  end

  it "provides help suggestions for missing command" do
    error = described_class.new
    
    expect(error.message).to include("No command specified")
    expect(error.full_message).to include("Common commands:")
  end
end

RSpec.describe GemDock::MissingArgumentError do
  it "provides command-specific help" do
    error = described_class.new("provision create", "RUBY_VERSION")
    
    expect(error.message).to include("Missing required argument 'RUBY_VERSION'")
    expect(error.full_message).to include("gemdock help provision create")
    expect(error.details[:command]).to eq("provision create")
    expect(error.details[:argument]).to eq("RUBY_VERSION")
  end
end

RSpec.describe GemDock::StateFileCorruptedError do
  it "provides recovery suggestions" do
    error = described_class.new("/path/to/state.yml", "YAML parse error")
    
    expect(error.message).to include("State file is corrupted")
    expect(error.message).to include("/path/to/state.yml")
    expect(error.full_message).to include("Backup the corrupted file")
    expect(error.full_message).to include("gemdock config reset")
    expect(error.details[:file_path]).to eq("/path/to/state.yml")
    expect(error.details[:error]).to eq("YAML parse error")
  end
end

RSpec.describe GemDock::ConfigFileCorruptedError do
  it "provides YAML fix suggestions" do
    error = described_class.new("/path/to/config.yml", "invalid YAML")
    
    expect(error.message).to include("Configuration file is corrupted")
    expect(error.full_message).to include("Check YAML syntax")
    expect(error.full_message).to include("gemdock config reset")
    expect(error.details[:file_path]).to eq("/path/to/config.yml")
  end
end

RSpec.describe GemDock::InsufficientResourcesError do
  it "provides resource management suggestions" do
    error = described_class.new("memory", "4GB", "2GB")
    
    expect(error.message).to include("Insufficient memory")
    expect(error.message).to include("required 4GB")
    expect(error.message).to include("available 2GB")
    expect(error.full_message).to include("Docker Desktop settings")
    expect(error.full_message).to include("gemdock clean --all")
    expect(error.details[:resource_type]).to eq("memory")
    expect(error.details[:required]).to eq("4GB")
    expect(error.details[:available]).to eq("2GB")
  end
end
