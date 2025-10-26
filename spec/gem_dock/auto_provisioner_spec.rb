require "spec_helper"
require "gem_dock/auto_provisioner"
require "tmpdir"
require "stringio"

RSpec.describe GemDock::AutoProvisioner do
  let(:provisioner) { instance_double(GemDock::ContainerProvisioner) }
  let(:lifecycle) { instance_double(GemDock::ContainerLifecycle) }
  let(:state_manager) { instance_double(GemDock::StateManager) }
  let(:config_manager) { instance_double(GemDock::ConfigManager) }
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }

  let(:auto_provisioner) do
    described_class.new(
      provisioner: provisioner,
      lifecycle: lifecycle,
      state_manager: state_manager,
      config_manager: config_manager,
      logger: logger
    )
  end

  let(:ruby_version) { "3.2.0" }
  let(:tmpdir) { Dir.mktmpdir }
  let(:compose_file) { File.join(tmpdir, ".gemdock", "docker-compose-3_2_0.yml") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "#ensure_ready" do
    context "when container is already running" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "running", container_id: "abc123" })
        allow(lifecycle).to receive(:start)
        allow(provisioner).to receive(:provision)
      end

      it "returns true immediately" do
        result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(result).to be true
      end

      it "does not start or provision" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(lifecycle).not_to have_received(:start)
        expect(provisioner).not_to have_received(:provision)
      end

      it "logs debug message" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(logger).to have_received(:debug).with("Container already running")
      end
    end

    context "when container is stopped" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "stopped", container_id: "abc123" })

        # Create compose file
        FileUtils.mkdir_p(File.dirname(compose_file))
        File.write(compose_file, "version: '3.8'")

        allow(provisioner).to receive(:compose_file_path).and_return(compose_file)
        allow(lifecycle).to receive(:start).and_return(true)
      end

      it "starts the container without prompting" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(lifecycle).to have_received(:start).with(ruby_version, compose_file: compose_file)
      end

      it "returns true on successful start" do
        result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(result).to be true
      end

      it "logs info message" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(logger).to have_received(:info).with("Starting stopped container", ruby_version: ruby_version)
      end
    end

    context "when container is stopped but compose file missing" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "stopped", container_id: "abc123" })

        allow(provisioner).to receive(:compose_file_path).and_return(compose_file)
        allow(provisioner).to receive(:provision).and_return(compose_file)
        allow(lifecycle).to receive(:start).and_return(true)
        allow(config_manager).to receive(:auto_provision?).and_return(true)
      end

      it "reprovisions the container" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(provisioner).to have_received(:provision)
        expect(lifecycle).to have_received(:start)
      end

      it "logs warning" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(logger).to have_received(:warn).with("Compose file not found, reprovisioning", compose_file: compose_file)
      end
    end

    context "when container is not provisioned with auto_provision enabled" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "not_provisioned" })

        allow(config_manager).to receive(:auto_provision?).and_return(true)
        allow(provisioner).to receive(:provision).and_return(compose_file)
        allow(lifecycle).to receive(:start).and_return(true)
      end

      it "provisions and starts the container" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(provisioner).to have_received(:provision).with(ruby_version, project_path: tmpdir)
        expect(lifecycle).to have_received(:start).with(ruby_version, compose_file: compose_file)
      end

      it "returns true on success" do
        result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(result).to be true
      end

      it "logs provisioning steps" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(logger).to have_received(:info).with("Provisioning new container", ruby_version: ruby_version)
        expect(logger).to have_received(:info).with("Container provisioned and started successfully", ruby_version: ruby_version)
      end
    end

    context "when container is not provisioned with auto_provision disabled" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "not_provisioned" })

        allow(config_manager).to receive(:auto_provision?).and_return(false)
      end

      context "in TTY mode with user confirmation" do
        before do
          allow(auto_provisioner).to receive(:tty_available?).and_return(true)
          allow(provisioner).to receive(:provision).and_return(compose_file)
          allow(lifecycle).to receive(:start).and_return(true)
        end

        it "prompts user and provisions on 'y'" do
          allow(GemDock::PromptHelper).to receive(:yes_no).and_return(true)

          result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(result).to be true
          expect(provisioner).to have_received(:provision)
        end

        it "prompts user and provisions on 'yes'" do
          allow(GemDock::PromptHelper).to receive(:yes_no).and_return(true)

          result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(result).to be true
          expect(provisioner).to have_received(:provision)
        end

        it "prompts user and cancels on 'n'" do
          allow(GemDock::PromptHelper).to receive(:yes_no).and_return(false)

          result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(result).to be false
          expect(provisioner).not_to have_received(:provision)
        end

        it "reprompts on invalid input then accepts 'y'" do
          allow(GemDock::PromptHelper).to receive(:yes_no).and_return(true)

          result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(result).to be true
        end

        it "logs user decline" do
          allow(GemDock::PromptHelper).to receive(:yes_no).and_return(false)

          auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(logger).to have_received(:info).with("User declined provisioning", ruby_version: ruby_version)
        end
      end

      context "in non-TTY mode (CI/CD)" do
        before do
          allow(auto_provisioner).to receive(:tty_available?).and_return(false)
          allow(provisioner).to receive(:provision)
        end

        it "returns false without provisioning" do
          result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(result).to be false
          expect(provisioner).not_to have_received(:provision)
        end

        it "logs error with suggestion" do
          auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

          expect(logger).to have_received(:error).with(
            "Auto-provisioning is disabled and no TTY available",
            hash_including(ruby_version: ruby_version, suggestion: kind_of(String))
          )
        end
      end
    end

    context "when provisioning fails" do
      before do
        allow(state_manager).to receive(:container_state).with(ruby_version)
          .and_return({ 'status' => "not_provisioned" })

        allow(config_manager).to receive(:auto_provision?).and_return(true)
        allow(provisioner).to receive(:provision).and_return(compose_file)
        allow(lifecycle).to receive(:start).and_return(false)
      end

      it "returns false" do
        result = auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(result).to be false
      end

      it "logs error" do
        auto_provisioner.ensure_ready(ruby_version, project_path: tmpdir)

        expect(logger).to have_received(:error).with(
          "Failed to start provisioned container",
          ruby_version: ruby_version
        )
      end
    end
  end

  describe "#ci_mode?" do
    after do
      # Clean up environment variables after each test
      ENV.delete("CI")
      ENV.delete("CONTINUOUS_INTEGRATION")
      ENV.delete("GITHUB_ACTIONS")
      ENV.delete("GITLAB_CI")
      ENV.delete("CIRCLECI")
      ENV.delete("JENKINS_HOME")
      ENV.delete("BUILDKITE")
    end

    it "returns true when CI env var is set" do
      ENV["CI"] = "true"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns true when CONTINUOUS_INTEGRATION is set" do
      ENV["CONTINUOUS_INTEGRATION"] = "true"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns true when GITHUB_ACTIONS is set" do
      ENV["GITHUB_ACTIONS"] = "true"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns true when GITLAB_CI is set" do
      ENV["GITLAB_CI"] = "true"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns true when CIRCLECI is set" do
      ENV["CIRCLECI"] = "true"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns true when JENKINS_HOME is set" do
      ENV["JENKINS_HOME"] = "/var/jenkins"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns true when BUILDKITE is set" do
      ENV["BUILDKITE"] = "true"
      expect(auto_provisioner.ci_mode?).to be true
    end

    it "returns false when no CI vars are set" do
      # Ensure all CI vars are unset
      ENV.delete("CI")
      ENV.delete("CONTINUOUS_INTEGRATION")
      ENV.delete("GITHUB_ACTIONS")
      ENV.delete("GITLAB_CI")
      ENV.delete("CIRCLECI")
      ENV.delete("JENKINS_HOME")
      ENV.delete("BUILDKITE")

      expect(auto_provisioner.ci_mode?).to be false
    end
  end

  describe "#tty_available?" do
    it "returns false when in CI mode" do
      allow(auto_provisioner).to receive(:ci_mode?).and_return(true)
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdout).to receive(:tty?).and_return(true)

      expect(auto_provisioner.tty_available?).to be false
    end

    it "returns false when stdin is not a TTY" do
      allow(auto_provisioner).to receive(:ci_mode?).and_return(false)
      allow($stdin).to receive(:tty?).and_return(false)
      allow($stdout).to receive(:tty?).and_return(true)

      expect(auto_provisioner.tty_available?).to be false
    end

    it "returns false when stdout is not a TTY" do
      allow(auto_provisioner).to receive(:ci_mode?).and_return(false)
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdout).to receive(:tty?).and_return(false)

      expect(auto_provisioner.tty_available?).to be false
    end

    it "returns true when not in CI and both stdin/stdout are TTY" do
      allow(auto_provisioner).to receive(:ci_mode?).and_return(false)
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdout).to receive(:tty?).and_return(true)

      expect(auto_provisioner.tty_available?).to be true
    end
  end

  describe "#with_progress" do
    context "when TTY is available" do
      before do
        allow(auto_provisioner).to receive(:tty_available?).and_return(true)
      end

      it "prints progress message and done" do
        expect {
          auto_provisioner.send(:with_progress, "Testing") { "result" }
        }.to output("Testing... done.\n").to_stdout
      end

      it "returns block result" do
        result = auto_provisioner.send(:with_progress, "Testing") { 42 }

        expect(result).to eq(42)
      end
    end

    context "when TTY is not available" do
      before do
        allow(auto_provisioner).to receive(:tty_available?).and_return(false)
      end

      it "logs message instead of printing" do
        auto_provisioner.send(:with_progress, "Testing") { "result" }

        expect(logger).to have_received(:info).with("Testing")
      end

      it "returns block result" do
        result = auto_provisioner.send(:with_progress, "Testing") { 42 }

        expect(result).to eq(42)
      end
    end
  end
end
