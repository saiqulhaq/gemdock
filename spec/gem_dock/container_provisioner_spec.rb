require "spec_helper"
require "gem_dock/container_provisioner"
require "tmpdir"
require "yaml"

RSpec.describe GemDock::ContainerProvisioner do
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:provisioner) { described_class.new(logger: logger) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:ruby_version) { "3.2.0" }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "#provision" do
    context "with valid parameters" do
      it "generates docker-compose.yml file" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)

        expect(File.exist?(compose_file)).to be true
      end

      it "returns the path to compose file" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)

        expect(compose_file).to eq(File.join(tmpdir, "docker-compose-3_2_0.yml"))
      end

      it "creates compose file with correct structure" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        expect(config["version"]).to eq("3.8")
        expect(config["services"]).to have_key("ruby")
        expect(config["volumes"]).to have_key("bundler_data_ruby_3_2_0")
        expect(config["networks"]).to have_key("gemdock")
      end

      it "uses correct Ruby image" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        expect(config["services"]["ruby"]["image"]).to eq("ruby:3.2.0")
      end

      it "sets correct container name" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        expect(config["services"]["ruby"]["container_name"]).to eq("gemdock-ruby-3_2_0")
      end

      it "mounts project directory as /app" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        volumes = config["services"]["ruby"]["volumes"]
        expect(volumes).to include("#{tmpdir}:/app")
      end

      it "mounts bundler data volume" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        volumes = config["services"]["ruby"]["volumes"]
        expect(volumes).to include("bundler_data_ruby_3_2_0:/usr/local/bundle")
      end

      it "sets working directory to /app" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        expect(config["services"]["ruby"]["working_dir"]).to eq("/app")
      end

      it "uses sleep infinity as command" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        expect(config["services"]["ruby"]["command"]).to eq("sleep infinity")
      end

      it "sets bundler environment variables" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        env = config["services"]["ruby"]["environment"]
        expect(env["BUNDLE_PATH"]).to eq("/usr/local/bundle")
        expect(env["GEM_HOME"]).to eq("/usr/local/bundle")
        expect(env["BUNDLE_APP_CONFIG"]).to eq("/usr/local/bundle")
      end

      it "creates named volume with correct name" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        volume_name = "bundler_data_ruby_3_2_0"
        expect(config["volumes"][volume_name]["name"]).to eq(volume_name)
      end

      it "creates gemdock network" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        config = YAML.load_file(compose_file)

        expect(config["networks"]["gemdock"]["name"]).to eq("gemdock_network")
      end

      it "logs provisioning start" do
        provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)

        expect(logger).to have_received(:info).with(
          "Provisioning container",
          hash_including(ruby_version: ruby_version)
        )
      end

      it "logs provisioning success" do
        provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)

        expect(logger).to have_received(:info).with(
          "Container provisioned successfully",
          hash_including(ruby_version: ruby_version)
        )
      end
    end

    context "with default compose_dir" do
      it "creates .gemdock directory in project path" do
        provisioner.provision(ruby_version, project_path: tmpdir)

        gemdock_dir = File.join(tmpdir, ".gemdock")
        expect(File.directory?(gemdock_dir)).to be true
      end

      it "places compose file in .gemdock directory" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir)

        expect(compose_file).to eq(File.join(tmpdir, ".gemdock", "docker-compose-3_2_0.yml"))
      end
    end

    context "with invalid ruby_version" do
      it "raises ValidationError for invalid format" do
        expect {
          provisioner.provision("invalid", project_path: tmpdir)
        }.to raise_error(GemDock::Validators::ValidationError, /Invalid Ruby version format/)
      end
    end

    context "with invalid project_path" do
      it "raises ArgumentError when path doesn't exist" do
        expect {
          provisioner.provision(ruby_version, project_path: "/nonexistent/path")
        }.to raise_error(ArgumentError, /does not exist/)
      end

      it "raises ArgumentError when path is not a directory" do
        file_path = File.join(tmpdir, "not_a_dir")
        File.write(file_path, "content")

        expect {
          provisioner.provision(ruby_version, project_path: file_path)
        }.to raise_error(ArgumentError, /is not a directory/)
      end
    end

    context "with different Ruby versions" do
      it "generates unique compose files for each version" do
        file1 = provisioner.provision("3.2.0", project_path: tmpdir, compose_dir: tmpdir)
        file2 = provisioner.provision("3.1.0", project_path: tmpdir, compose_dir: tmpdir)

        expect(file1).to end_with("docker-compose-3_2_0.yml")
        expect(file2).to end_with("docker-compose-3_1_0.yml")
        expect(File.exist?(file1)).to be true
        expect(File.exist?(file2)).to be true
      end

      it "uses different volume names for each version" do
        file1 = provisioner.provision("3.2.0", project_path: tmpdir, compose_dir: tmpdir)
        file2 = provisioner.provision("2.7.8", project_path: tmpdir, compose_dir: tmpdir)

        config1 = YAML.load_file(file1)
        config2 = YAML.load_file(file2)

        expect(config1["volumes"].keys.first).to eq("bundler_data_ruby_3_2_0")
        expect(config2["volumes"].keys.first).to eq("bundler_data_ruby_2_7_8")
      end
    end

    context "when compose file already exists" do
      it "overwrites existing file" do
        compose_file = provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        
        # Modify the file
        File.write(compose_file, "old content")
        
        # Provision again
        provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        
        # Should have valid YAML, not "old content"
        config = YAML.load_file(compose_file)
        expect(config["version"]).to eq("3.8")
      end
    end
  end

  describe "#provisioned?" do
    it "returns true when compose file exists" do
      provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)

      expect(provisioner.provisioned?(ruby_version, compose_dir: tmpdir)).to be true
    end

    it "returns false when compose file doesn't exist" do
      expect(provisioner.provisioned?(ruby_version, compose_dir: tmpdir)).to be false
    end

    it "checks .gemdock directory by default" do
      provisioner.provision(ruby_version, project_path: tmpdir)

      expect(provisioner.provisioned?(ruby_version, compose_dir: File.join(tmpdir, ".gemdock"))).to be true
    end
  end

  describe "#deprovision" do
    context "when compose file exists" do
      before do
        provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
      end

      it "removes the compose file" do
        compose_file = File.join(tmpdir, "docker-compose-3_2_0.yml")
        expect(File.exist?(compose_file)).to be true

        provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(File.exist?(compose_file)).to be false
      end

      it "returns true" do
        result = provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(result).to be true
      end

      it "logs deprovisioning" do
        provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(logger).to have_received(:info).with(
          "Deprovisioning container",
          hash_including(ruby_version: ruby_version)
        )
        expect(logger).to have_received(:info).with(
          "Container deprovisioned",
          ruby_version: ruby_version
        )
      end
    end

    context "when compose file doesn't exist" do
      it "returns true without error" do
        result = provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(result).to be true
      end

      it "logs debug message" do
        provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(logger).to have_received(:debug).with(
          "Compose file not found",
          compose_file: kind_of(String)
        )
      end
    end

    context "when deletion fails" do
      before do
        provisioner.provision(ruby_version, project_path: tmpdir, compose_dir: tmpdir)
        compose_file = File.join(tmpdir, "docker-compose-3_2_0.yml")
        
        # Make file read-only to simulate deletion failure
        File.chmod(0444, compose_file)
        File.chmod(0555, tmpdir)
      end

      after do
        # Restore permissions for cleanup
        File.chmod(0755, tmpdir)
      end

      it "returns false" do
        result = provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(result).to be false
      end

      it "logs error" do
        provisioner.deprovision(ruby_version, compose_dir: tmpdir)

        expect(logger).to have_received(:error).with(
          "Failed to deprovision container",
          hash_including(ruby_version: ruby_version, error: kind_of(String))
        )
      end
    end
  end

  describe "#compose_file_path" do
    it "returns the correct path" do
      path = provisioner.compose_file_path(ruby_version, compose_dir: tmpdir)

      expect(path).to eq(File.join(tmpdir, "docker-compose-3_2_0.yml"))
    end

    it "uses .gemdock directory by default" do
      path = provisioner.compose_file_path(ruby_version)

      expect(path).to end_with(".gemdock/docker-compose-3_2_0.yml")
    end
  end
end
