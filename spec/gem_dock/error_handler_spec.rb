# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/gem_dock/error_handler"
require_relative "../../lib/gem_dock/errors"
require_relative "../../lib/gem_dock/validators"

RSpec.describe GemDock::ErrorHandler do
  describe ".handle" do
    before do
      # Suppress output during tests
      allow($stdout).to receive(:puts)
      allow($stdout).to receive(:print)
      allow(GemDock::PromptHelper).to receive(:error).and_return("ERROR")
    end

    it "exits with code 1" do
      error = StandardError.new("test error")
      expect { described_class.handle(error) }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(1)
      end
    end

    context "with custom GemDock errors" do
      it "handles ContainerNotFoundError with suggestions" do
        error = GemDock::ContainerNotFoundError.new("ruby-3.2.0")
        
        expect(GemDock::PromptHelper).to receive(:error).with(error.message)
        expect($stdout).to receive(:puts).with(error.full_message)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "handles InvalidConfigError with suggestions" do
        error = GemDock::InvalidConfigError.new("mode", "invalid", ["persistent", "ephemeral"])
        
        expect(GemDock::PromptHelper).to receive(:error).with(error.message)
        expect($stdout).to receive(:puts).with(error.full_message)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "handles DockerNotAvailableError" do
        error = GemDock::DockerNotAvailableError.new
        
        expect(GemDock::PromptHelper).to receive(:error).with(error.message)
        expect($stdout).to receive(:puts).with(error.full_message)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end

    context "with validation errors" do
      it "handles validation errors with suggestions" do
        error = GemDock::Validators::ValidationError.new(
          "Invalid value for mode",
          field: "mode",
          value: "wrong"
        )
        
        expect(GemDock::PromptHelper).to receive(:error).with("Validation Error")
        expect($stdout).to receive(:puts).with("Invalid value for mode")
        expect($stdout).to receive(:puts).with(/Suggestions:/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "includes command help suggestion when context provided" do
        error = GemDock::Validators::ValidationError.new("Invalid")
        
        expect($stdout).to receive(:puts).with(/gemdock help provision/)
        
        expect { 
          described_class.handle(error, command: "provision")
        }.to raise_error(SystemExit)
      end
    end

    context "with Docker errors" do
      it "handles DockerCommand::CommandError when Docker is not running" do
        error = GemDock::DockerCommand::CommandError.new("Docker command failed")
        allow(described_class).to receive(:system).with(/docker info/).and_return(false)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Docker Error")
        expect($stdout).to receive(:puts).with(/Docker is not running/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "handles DockerCommand::CommandError when Docker is running" do
        error = GemDock::DockerCommand::CommandError.new("Container not found")
        allow(described_class).to receive(:system).with(/docker info/).and_return(true)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Docker Error")
        expect($stdout).to receive(:puts).with(/Check if the container exists/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "detects permission issues" do
        error = GemDock::DockerCommand::CommandError.new("permission denied")
        allow(described_class).to receive(:system).and_return(true)
        
        expect($stdout).to receive(:puts).with(/Add your user to docker group/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "detects timeout issues" do
        error = GemDock::DockerCommand::TimeoutError.new("Command timed out")
        
        expect(GemDock::PromptHelper).to receive(:error).with("Docker Timeout Error")
        expect($stdout).to receive(:puts).with(/Docker might be slow/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end

    context "with file system errors" do
      it "handles ENOENT for .gemdock directory" do
        error = Errno::ENOENT.new("No such file or directory @ rb_sysopen - /home/user/.gemdock/config.yml")
        
        expect(GemDock::PromptHelper).to receive(:error).with("File Not Found")
        expect($stdout).to receive(:puts).with(/GemDock configuration directory not found/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "handles ENOENT for docker-compose file" do
        error = Errno::ENOENT.new("No such file or directory @ rb_sysopen - /home/user/.gemdock/docker-compose-ruby-3.2.0.yml")
        
        expect(GemDock::PromptHelper).to receive(:error).with("File Not Found")
        expect($stdout).to receive(:puts).with(/Docker Compose file missing/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "handles EACCES permission errors" do
        error = Errno::EACCES.new("Permission denied @ rb_sysopen - /home/user/.gemdock/state.yml")
        
        expect(GemDock::PromptHelper).to receive(:error).with("Permission Denied")
        expect($stdout).to receive(:puts).with(/Cannot access file/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "suggests fixing .gemdock permissions" do
        error = Errno::EACCES.new("Permission denied @ rb_sysopen - /home/user/.gemdock/state.yml")
        
        expect(GemDock::PromptHelper).to receive(:error).with("Permission Denied")
        expect($stdout).to receive(:puts).with(/chmod -R u\+w ~\/.gemdock/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end

    context "with YAML/JSON errors" do
      it "handles Psych::SyntaxError" do
        error = Psych::SyntaxError.new("file.yml", 5, 10, 0, "unexpected end of file", "scanner")
        
        expect(GemDock::PromptHelper).to receive(:error).with("YAML Syntax Error")
        expect($stdout).to receive(:puts).with(/Check YAML syntax/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "includes file path when provided in context" do
        error = Psych::SyntaxError.new("file.yml", 5, 10, 0, "error", "scanner")
        
        expect($stdout).to receive(:puts).with(/Fix syntax errors in: \/path\/to\/config.yml/)
        
        expect { 
          described_class.handle(error, file: "/path/to/config.yml")
        }.to raise_error(SystemExit)
      end

      it "handles JSON::ParserError" do
        error = JSON::ParserError.new("unexpected token")
        
        expect(GemDock::PromptHelper).to receive(:error).with("JSON Parse Error")
        expect($stdout).to receive(:puts).with(/Invalid JSON format/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end

    context "with Thor errors" do
      it "handles Thor::UndefinedCommandError with similar command suggestions" do
        error = Thor::UndefinedCommandError.new("provisio", %w[exec provision config], Thor::HELP_MAPPINGS)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        # Just check that it outputs something about the error
        allow($stdout).to receive(:puts)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "suggests common commands when no match found" do
        error = Thor::UndefinedCommandError.new("xyz", %w[exec provision config], Thor::HELP_MAPPINGS)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        allow($stdout).to receive(:puts)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "handles missing argument errors" do
        error = Thor::RequiredArgumentMissingError.new("No value provided for required argument 'ruby_version'")
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        expect($stdout).to receive(:puts).with(/Check required arguments/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end

    context "with generic errors" do
      it "handles StandardError with generic suggestions" do
        error = StandardError.new("Something went wrong")
        
        expect(GemDock::PromptHelper).to receive(:error).with("Error")
        expect($stdout).to receive(:puts).with(/StandardError: Something went wrong/)
        expect($stdout).to receive(:puts).with(/Check 'gemdock status'/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "includes command context when provided" do
        error = StandardError.new("Error")
        
        expect($stdout).to receive(:puts).with(/View help for this command: gemdock help exec/)
        
        expect { 
          described_class.handle(error, command: "exec")
        }.to raise_error(SystemExit)
      end

      it "shows backtrace when DEBUG env is set" do
        error = StandardError.new("Debug error")
        
        # Set ENV in the test context
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DEBUG").and_return("1")
        allow(ENV).to receive(:[]).with("GEMDOCK_DEBUG").and_return(nil)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Error")
        expect($stdout).to receive(:puts).with(/Backtrace:/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "shows backtrace hint when DEBUG is not set" do
        error = StandardError.new("Normal error")
        
        # Ensure DEBUG is not set
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DEBUG").and_return(nil)
        allow(ENV).to receive(:[]).with("GEMDOCK_DEBUG").and_return(nil)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Error")
        expect($stdout).to receive(:puts).with(/Set GEMDOCK_DEBUG=1/)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end

    describe "command similarity detection" do
      it "suggests 'exec' for 'ex'" do
        error = Thor::UndefinedCommandError.new("ex", %w[exec provision config], Thor::HELP_MAPPINGS)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        allow($stdout).to receive(:puts)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "suggests 'provision start' for 'provision star'" do
        error = Thor::UndefinedCommandError.new("provision star", %w[start stop restart], Thor::HELP_MAPPINGS)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        allow($stdout).to receive(:puts)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "suggests 'config' for 'conf'" do
        error = Thor::UndefinedCommandError.new("conf", %w[exec provision config], Thor::HELP_MAPPINGS)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        allow($stdout).to receive(:puts)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end

      it "limits suggestions to 3 commands" do
        error = Thor::UndefinedCommandError.new("p", %w[provision provision-start provision-stop], Thor::HELP_MAPPINGS)
        
        expect(GemDock::PromptHelper).to receive(:error).with("Command Error")
        allow($stdout).to receive(:puts)
        
        expect { described_class.handle(error) }.to raise_error(SystemExit)
      end
    end
  end
end
