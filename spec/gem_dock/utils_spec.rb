require "spec_helper"
require "gem_dock/utils"

RSpec.describe GemDock::Utils do
  describe ".valid_ruby_version?" do
    it "accepts valid Ruby version format" do
      expect(described_class.valid_ruby_version?("3.2.0")).to be true
      expect(described_class.valid_ruby_version?("2.7.8")).to be true
      expect(described_class.valid_ruby_version?("3.3.10")).to be true
    end

    it "rejects invalid formats" do
      expect(described_class.valid_ruby_version?("3.2")).to be false
      expect(described_class.valid_ruby_version?("3")).to be false
      expect(described_class.valid_ruby_version?("3.2.0.1")).to be false
      expect(described_class.valid_ruby_version?("v3.2.0")).to be false
      expect(described_class.valid_ruby_version?("")).to be false
      expect(described_class.valid_ruby_version?(nil)).to be false
    end
  end

  describe ".sanitize_version" do
    it "converts dots to underscores" do
      expect(described_class.sanitize_version("3.2.0")).to eq("3_2_0")
      expect(described_class.sanitize_version("2.7.8")).to eq("2_7_8")
    end

    it "handles edge cases" do
      expect(described_class.sanitize_version("3.2.0.1")).to eq("3_2_0_1")
      expect(described_class.sanitize_version("3")).to eq("3")
    end
  end

  describe ".container_name" do
    it "generates proper container name" do
      expect(described_class.container_name("3.2.0")).to eq("gemdock-ruby-3_2_0")
      expect(described_class.container_name("2.7.8")).to eq("gemdock-ruby-2_7_8")
    end
  end

  describe ".volume_name" do
    it "generates proper volume name" do
      expect(described_class.volume_name("3.2.0")).to eq("bundler_data_ruby_3_2_0")
      expect(described_class.volume_name("2.7.8")).to eq("bundler_data_ruby_2_7_8")
    end
  end

  describe "file path utilities" do
    describe ".gemdock_dir" do
      it "returns .gemdock directory in current directory" do
        expect(described_class.gemdock_dir).to eq(File.join(Dir.pwd, ".gemdock"))
      end

      it "accepts custom project root" do
        expect(described_class.gemdock_dir("/custom/path")).to eq("/custom/path/.gemdock")
      end
    end

    describe ".state_file_path" do
      it "returns state.yml path" do
        expect(described_class.state_file_path).to eq(File.join(Dir.pwd, ".gemdock", "state.yml"))
      end

      it "accepts custom project root" do
        expect(described_class.state_file_path("/custom/path")).to eq("/custom/path/.gemdock/state.yml")
      end
    end

    describe ".config_file_path" do
      it "returns config.yml path" do
        expect(described_class.config_file_path).to eq(File.join(Dir.pwd, ".gemdock", "config.yml"))
      end
    end

    describe ".log_file_path" do
      it "returns gemdock.log path" do
        expect(described_class.log_file_path).to eq(File.join(Dir.pwd, ".gemdock", "gemdock.log"))
      end
    end

    describe ".ensure_gemdock_dir" do
      it "creates .gemdock directory if it doesn't exist" do
        Dir.mktmpdir do |tmpdir|
          gemdock_dir = described_class.ensure_gemdock_dir(tmpdir)
          expect(File.directory?(gemdock_dir)).to be true
          expect(gemdock_dir).to eq(File.join(tmpdir, ".gemdock"))
        end
      end

      it "returns existing directory without error" do
        Dir.mktmpdir do |tmpdir|
          gemdock_dir = File.join(tmpdir, ".gemdock")
          FileUtils.mkdir_p(gemdock_dir)
          
          result = described_class.ensure_gemdock_dir(tmpdir)
          expect(result).to eq(gemdock_dir)
          expect(File.directory?(result)).to be true
        end
      end
    end
  end

  describe "timestamp utilities" do
    describe ".format_timestamp" do
      it "formats current time by default" do
        timestamp = described_class.format_timestamp
        expect(timestamp).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      end

      it "formats given time" do
        time = Time.utc(2025, 10, 22, 14, 30, 0)
        expect(described_class.format_timestamp(time)).to eq("2025-10-22T14:30:00Z")
      end
    end

    describe ".parse_timestamp" do
      it "parses ISO 8601 timestamps" do
        time = described_class.parse_timestamp("2025-10-22T14:30:00Z")
        expect(time).to be_a(Time)
        expect(time.year).to eq(2025)
        expect(time.month).to eq(10)
        expect(time.day).to eq(22)
      end

      it "raises error for invalid timestamps" do
        expect { described_class.parse_timestamp("invalid") }.to raise_error(
          ArgumentError,
          /Invalid timestamp format/
        )
      end
    end
  end

  describe ".valid_container_name?" do
    it "accepts valid gemdock container names" do
      expect(described_class.valid_container_name?("gemdock-ruby-3_2_0")).to be true
      expect(described_class.valid_container_name?("gemdock-ruby-2_7_8")).to be true
    end

    it "rejects invalid names" do
      expect(described_class.valid_container_name?("gemdock-ruby-3.2.0")).to be false
      expect(described_class.valid_container_name?("other-ruby-3_2_0")).to be false
      expect(described_class.valid_container_name?("gemdock-ruby-3_2")).to be false
      expect(described_class.valid_container_name?("")).to be false
    end
  end

  describe ".version_from_container_name" do
    it "extracts version from valid container name" do
      expect(described_class.version_from_container_name("gemdock-ruby-3_2_0")).to eq("3.2.0")
      expect(described_class.version_from_container_name("gemdock-ruby-2_7_8")).to eq("2.7.8")
    end

    it "returns nil for invalid names" do
      expect(described_class.version_from_container_name("gemdock-ruby-3.2.0")).to be_nil
      expect(described_class.version_from_container_name("other-ruby-3_2_0")).to be_nil
      expect(described_class.version_from_container_name("invalid")).to be_nil
    end
  end

  describe ".version_from_volume_name" do
    it "extracts version from valid volume name" do
      expect(described_class.version_from_volume_name("bundler_data_ruby_3_2_0")).to eq("3.2.0")
      expect(described_class.version_from_volume_name("bundler_data_ruby_2_7_8")).to eq("2.7.8")
    end

    it "returns nil for invalid names" do
      expect(described_class.version_from_volume_name("bundler_data_ruby_3.2.0")).to be_nil
      expect(described_class.version_from_volume_name("other_data_ruby_3_2_0")).to be_nil
      expect(described_class.version_from_volume_name("invalid")).to be_nil
    end
  end
end
