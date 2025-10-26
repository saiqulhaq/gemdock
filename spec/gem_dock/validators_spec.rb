require "spec_helper"
require "gem_dock/validators"

RSpec.describe GemDock::Validators do
  describe "container state validation" do
    describe ".validate_container_status!" do
      it "accepts valid statuses" do
        expect { described_class.validate_container_status!("running") }.not_to raise_error
        expect { described_class.validate_container_status!("stopped") }.not_to raise_error
        expect { described_class.validate_container_status!("not_provisioned") }.not_to raise_error
      end

      it "rejects invalid status" do
        expect { described_class.validate_container_status!("invalid") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid container status/
        )
      end
    end

    describe ".validate_container_id!" do
      it "accepts nil container_id" do
        expect { described_class.validate_container_id!(nil) }.not_to raise_error
      end

      it "accepts valid 64-char hex container_id" do
        valid_id = "a" * 64
        expect { described_class.validate_container_id!(valid_id) }.not_to raise_error
      end

      it "rejects invalid container_id format" do
        expect { described_class.validate_container_id!("invalid") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid container_id format/
        )
      end
    end

    describe ".validate_timestamp!" do
      it "accepts valid ISO 8601 timestamp" do
        valid_timestamp = "2025-10-19T14:30:00Z"
        expect { described_class.validate_timestamp!(valid_timestamp) }.not_to raise_error
      end

      it "rejects invalid timestamp" do
        expect { described_class.validate_timestamp!("invalid") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid timestamp/
        )
      end
    end

    describe ".validate_volume_name!" do
      it "accepts matching volume name" do
        expect { described_class.validate_volume_name!("bundler_data_ruby_3_2_0", "3.2.0") }.not_to raise_error
      end

      it "accepts nil volume name" do
        expect { described_class.validate_volume_name!(nil, "3.2.0") }.not_to raise_error
      end

      it "rejects mismatched volume name" do
        expect { described_class.validate_volume_name!("wrong_name", "3.2.0") }.to raise_error(
          GemDock::Validators::ValidationError,
          /doesn't match Ruby version/
        )
      end
    end

    describe ".validate_state_transition!" do
      it "allows valid transitions" do
        expect { described_class.validate_state_transition!("not_provisioned", "running") }.not_to raise_error
        expect { described_class.validate_state_transition!("running", "stopped") }.not_to raise_error
        expect { described_class.validate_state_transition!("stopped", "running") }.not_to raise_error
        expect { described_class.validate_state_transition!("running", "not_provisioned") }.not_to raise_error
        expect { described_class.validate_state_transition!("stopped", "not_provisioned") }.not_to raise_error
      end

      it "rejects invalid transitions" do
        expect { described_class.validate_state_transition!("not_provisioned", "stopped") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid state transition/
        )
      end
    end
  end

  describe "configuration validation" do
    describe ".validate_mode!" do
      it "accepts valid modes" do
        expect { described_class.validate_mode!("persistent") }.not_to raise_error
        expect { described_class.validate_mode!("ephemeral") }.not_to raise_error
      end

      it "rejects invalid mode" do
        expect { described_class.validate_mode!("invalid") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid mode/
        )
      end
    end

    describe ".validate_boolean!" do
      it "accepts true and false" do
        expect { described_class.validate_boolean!(true, field: "test") }.not_to raise_error
        expect { described_class.validate_boolean!(false, field: "test") }.not_to raise_error
      end

      it "rejects non-boolean values" do
        expect { described_class.validate_boolean!("true", field: "test") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid boolean value/
        )
      end
    end

    describe ".validate_idle_timeout!" do
      it "accepts valid timeout values" do
        expect { described_class.validate_idle_timeout!(1) }.not_to raise_error
        expect { described_class.validate_idle_timeout!(24) }.not_to raise_error
        expect { described_class.validate_idle_timeout!(720) }.not_to raise_error
      end

      it "rejects values outside valid range" do
        expect { described_class.validate_idle_timeout!(0) }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid idle timeout/
        )
        expect { described_class.validate_idle_timeout!(721) }.to raise_error(
          GemDock::Validators::ValidationError
        )
      end

      it "rejects non-integer values" do
        expect { described_class.validate_idle_timeout!(24.5) }.to raise_error(
          GemDock::Validators::ValidationError
        )
      end
    end

    describe ".validate_ruby_version!" do
      it "accepts nil" do
        expect { described_class.validate_ruby_version!(nil) }.not_to raise_error
      end

      it "accepts valid Ruby version format" do
        expect { described_class.validate_ruby_version!("3.2.0") }.not_to raise_error
        expect { described_class.validate_ruby_version!("2.7.8") }.not_to raise_error
      end

      it "rejects invalid format" do
        expect { described_class.validate_ruby_version!("3.2") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid Ruby version format/
        )
      end
    end

    describe ".validate_log_level!" do
      it "accepts valid log levels" do
        %w[debug info warn error].each do |level|
          expect { described_class.validate_log_level!(level) }.not_to raise_error
        end
      end

      it "rejects invalid log level" do
        expect { described_class.validate_log_level!("verbose") }.to raise_error(
          GemDock::Validators::ValidationError,
          /Invalid log level/
        )
      end
    end
  end

  describe "cross-entity validation" do
    describe ".validate_current_ruby_exists!" do
      let(:containers) { {"3.2.0" => {}, "3.1.0" => {}} }

      it "accepts nil current_ruby" do
        expect { described_class.validate_current_ruby_exists!(nil, containers) }.not_to raise_error
      end

      it "accepts current_ruby that exists in containers" do
        expect { described_class.validate_current_ruby_exists!("3.2.0", containers) }.not_to raise_error
      end

      it "rejects current_ruby not in containers" do
        expect { described_class.validate_current_ruby_exists!("2.7.0", containers) }.to raise_error(
          GemDock::Validators::ValidationError,
          /not found in containers/
        )
      end
    end

    describe ".validate_container_id_consistency!" do
      it "accepts not_provisioned with nil container_id" do
        expect { described_class.validate_container_id_consistency!("not_provisioned", nil) }.not_to raise_error
      end

      it "accepts running with container_id" do
        expect { described_class.validate_container_id_consistency!("running", "a" * 64) }.not_to raise_error
      end

      it "accepts stopped with container_id" do
        expect { described_class.validate_container_id_consistency!("stopped", "a" * 64) }.not_to raise_error
      end

      it "rejects not_provisioned with container_id" do
        expect { described_class.validate_container_id_consistency!("not_provisioned", "abc123") }.to raise_error(
          GemDock::Validators::ValidationError,
          /not_provisioned.*has container_id/
        )
      end

      it "rejects running without container_id" do
        expect { described_class.validate_container_id_consistency!("running", nil) }.to raise_error(
          GemDock::Validators::ValidationError,
          /running.*has no container_id/
        )
      end
    end
  end

  describe "ValidationError" do
    it "includes field, value, and suggestion" do
      error = GemDock::Validators::ValidationError.new(
        "Test error",
        field: "test_field",
        value: "test_value",
        suggestion: "Try something else"
      )

      expect(error.field).to eq("test_field")
      expect(error.value).to eq("test_value")
      expect(error.suggestion).to eq("Try something else")
      expect(error.message).to include("Test error")
      expect(error.message).to include("Try something else")
    end
  end
end
