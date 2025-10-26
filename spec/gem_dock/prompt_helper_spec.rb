# frozen_string_literal: true

require "spec_helper"

RSpec.describe GemDock::PromptHelper do
  let(:prompt_helper) { described_class }

  describe ".prompts_available?" do
    context "when in CI mode" do
      before { allow(ENV).to receive(:[]).with("CI").and_return("true") }

      it "returns false" do
        expect(prompt_helper.prompts_available?).to be false
      end
    end

    context "when not in CI and TTY available" do
      before do
        allow(ENV).to receive(:[]).with("CI").and_return(nil)
        allow(ENV).to receive(:[]).with("GITHUB_ACTIONS").and_return(nil)
        allow(ENV).to receive(:[]).with("GITLAB_CI").and_return(nil)
        allow($stdin).to receive(:tty?).and_return(true)
      end

      it "returns true" do
        expect(prompt_helper.prompts_available?).to be true
      end
    end

    context "when not in CI but no TTY" do
      before do
        allow(ENV).to receive(:[]).with("CI").and_return(nil)
        allow(ENV).to receive(:[]).with("GITHUB_ACTIONS").and_return(nil)
        allow(ENV).to receive(:[]).with("GITLAB_CI").and_return(nil)
        allow($stdin).to receive(:tty?).and_return(false)
      end

      it "returns false" do
        expect(prompt_helper.prompts_available?).to be false
      end
    end
  end

  describe ".ci_mode?" do
    it "detects CI environment variable" do
      allow(ENV).to receive(:[]).with("CI").and_return("true")
      expect(prompt_helper.ci_mode?).to be true
    end

    it "detects GITHUB_ACTIONS environment" do
      allow(ENV).to receive(:[]).with("CI").and_return(nil)
      allow(ENV).to receive(:[]).with("GITHUB_ACTIONS").and_return("true")
      expect(prompt_helper.ci_mode?).to be true
    end

    it "detects GITLAB_CI environment" do
      allow(ENV).to receive(:[]).with("CI").and_return(nil)
      allow(ENV).to receive(:[]).with("GITHUB_ACTIONS").and_return(nil)
      allow(ENV).to receive(:[]).with("GITLAB_CI").and_return("true")
      expect(prompt_helper.ci_mode?).to be true
    end

    it "returns false when not in CI" do
      allow(ENV).to receive(:[]).with("CI").and_return(nil)
      allow(ENV).to receive(:[]).with("GITHUB_ACTIONS").and_return(nil)
      allow(ENV).to receive(:[]).with("GITLAB_CI").and_return(nil)
      expect(prompt_helper.ci_mode?).to be false
    end
  end

  describe ".yes_no" do
    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt for yes/no question" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        allow(prompt).to receive(:yes?).and_yield(double(default: nil)).and_return(true)

        result = prompt_helper.yes_no("Continue?", default: false)
        expect(result).to be true
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "returns default value and prints message" do
        expect { prompt_helper.yes_no("Continue?", default: true) }
          .to output(/Continue\?.*yes/).to_stdout
      end

      it "returns false when default is false" do
        result = nil
        expect { result = prompt_helper.yes_no("Continue?", default: false) }
          .to output(/Continue\?.*no/).to_stdout
        expect(result).to be false
      end
    end
  end

  describe ".select" do
    let(:choices) { ["Option 1", "Option 2", "Option 3"] }

    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt for selection" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        allow(prompt).to receive(:select).and_return("Option 2")

        result = prompt_helper.select("Choose:", choices)
        expect(result).to eq("Option 2")
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "returns default value" do
        result = nil
        expect { result = prompt_helper.select("Choose:", choices, default: "Option 2") }
          .to output(/Choose:.*Option 2/).to_stdout
        expect(result).to eq("Option 2")
      end

      it "returns first choice when no default" do
        result = nil
        expect { result = prompt_helper.select("Choose:", choices) }
          .to output(/Choose:.*Option 1/).to_stdout
        expect(result).to eq("Option 1")
      end
    end
  end

  describe ".multi_select" do
    let(:choices) { ["Item 1", "Item 2", "Item 3"] }

    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt for multi-selection" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        allow(prompt).to receive(:multi_select).and_return(["Item 1", "Item 3"])

        result = prompt_helper.multi_select("Select items:", choices)
        expect(result).to eq(["Item 1", "Item 3"])
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "returns default selections" do
        defaults = ["Item 2"]
        result = nil
        expect { result = prompt_helper.multi_select("Select items:", choices, default: defaults) }
          .to output(/Select items:.*Item 2/).to_stdout
        expect(result).to eq(defaults)
      end
    end
  end

  describe ".ask" do
    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt for text input" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        allow(prompt).to receive(:ask).and_yield(double(default: nil, required: nil)).and_return("user input")

        result = prompt_helper.ask("Enter value:")
        expect(result).to eq("user input")
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "returns default value" do
        result = nil
        expect { result = prompt_helper.ask("Enter value:", default: "default") }
          .to output(/Enter value:.*default/).to_stdout
        expect(result).to eq("default")
      end
    end
  end

  describe ".confirm_with_details" do
    let(:details) { ["Detail 1", "Detail 2"] }

    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "displays details and asks for confirmation" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        allow(prompt).to receive(:yes?).and_yield(double(default: nil)).and_return(true)

        expect { prompt_helper.confirm_with_details("Proceed?", details: details) }
          .to output(/Detail 1.*Detail 2/m).to_stdout
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "displays details and returns default" do
        result = nil
        expect do
          result = prompt_helper.confirm_with_details("Proceed?", details: details, default: true)
        end.to output(/Detail 1.*Detail 2.*Proceed\?.*yes/m).to_stdout
        expect(result).to be true
      end
    end
  end

  describe ".warn" do
    let(:message) { "This is a warning" }

    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt warn method" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        expect(prompt).to receive(:warn).with(message)

        prompt_helper.warn(message)
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "prints WARNING prefix" do
        expect { prompt_helper.warn(message) }
          .to output(/WARNING: This is a warning/).to_stdout
      end
    end
  end

  describe ".error" do
    let(:message) { "This is an error" }

    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt error method" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        expect(prompt).to receive(:error).with(message)

        prompt_helper.error(message)
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "prints ERROR prefix" do
        expect { prompt_helper.error(message) }
          .to output(/ERROR: This is an error/).to_stdout
      end
    end
  end

  describe ".success" do
    let(:message) { "Operation successful" }

    context "when prompts are available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(true)
      end

      it "uses TTY::Prompt ok method" do
        prompt = instance_double(TTY::Prompt)
        allow(prompt_helper).to receive(:prompt).and_return(prompt)
        expect(prompt).to receive(:ok).with(message)

        prompt_helper.success(message)
      end
    end

    context "when prompts are not available" do
      before do
        allow(prompt_helper).to receive(:prompts_available?).and_return(false)
      end

      it "prints checkmark prefix" do
        expect { prompt_helper.success(message) }
          .to output(/✓ Operation successful/).to_stdout
      end
    end
  end
end
