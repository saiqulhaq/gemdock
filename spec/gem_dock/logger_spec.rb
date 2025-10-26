require "spec_helper"
require "gem_dock/logger"
require "json"

RSpec.describe GemDock::Logger do
  let(:log_dir) { GemDock::Logger::LOG_DIR }
  let(:log_file) { GemDock::Logger::LOG_FILE }

  around do |example|
    # Use the real filesystem for this spec
    FileUtils.mkdir_p(log_dir)
    example.run
    FileUtils.rm_rf(log_dir)
  end

  describe "#initialize" do
    it "creates the log directory" do
      described_class.new
      expect(File.directory?(log_dir)).to be true
    end

    it "initializes the underlying logger with file rotation settings" do
      expect(::Logger).to receive(:new).with(
        log_file,
        GemDock::Logger::LOG_SHIFTS,
        GemDock::Logger::MAX_LOG_SIZE
      ).and_call_original
      described_class.new
    end
  end

  describe "logging methods" do
    subject(:logger) { described_class.new }

    let(:log_output) { File.read(log_file) }
    let(:log_entry) { JSON.parse(log_output.lines.last) }

    it "logs info messages with context" do
      logger.info("Container started", ruby_version: "3.2.0", container_id: "abc123")
      expect(log_entry["level"]).to eq("info")
      expect(log_entry["message"]).to eq("Container started")
      expect(log_entry["ruby_version"]).to eq("3.2.0")
      expect(log_entry["container_id"]).to eq("abc123")
      expect(log_entry).to have_key("timestamp")
    end

    it "logs warn messages" do
      logger.warn("Health check failed", attempt: 2)
      expect(log_entry["level"]).to eq("warn")
      expect(log_entry["message"]).to eq("Health check failed")
      expect(log_entry["attempt"]).to eq(2)
    end

    it "logs error messages" do
      logger.error("Operation failed", error_code: 500)
      expect(log_entry["level"]).to eq("error")
      expect(log_entry["message"]).to eq("Operation failed")
      expect(log_entry["error_code"]).to eq(500)
    end

    it "logs debug messages" do
      logger = described_class.new(level: ::Logger::DEBUG)
      logger.debug("Executing command", command: "ls -la")
      expect(log_entry["level"]).to eq("debug")
      expect(log_entry["message"]).to eq("Executing command")
      expect(log_entry["command"]).to eq("ls -la")
    end

    it "handles messages without context" do
      logger.info("Simple message")
      expect(log_entry["level"]).to eq("info")
      expect(log_entry["message"]).to eq("Simple message")
    end
  end

  describe "log levels" do
    it "does not log debug messages when level is INFO" do
      logger = described_class.new(level: ::Logger::INFO)
      logger.debug("This should not be logged")
      log_content = File.read(log_file)
      # The logger might write a header, so we check if it's empty or just has the header
      expect(log_content.lines.reject { |l| l.start_with?("#") }.join).to be_empty
    end

    it "logs info messages when level is INFO" do
      logger = described_class.new(level: ::Logger::INFO)
      logger.info("This should be logged")
      log_content = File.read(log_file)
      # The logger might write a header, so we check if it's empty or just has the header
      expect(log_content.lines.reject { |l| l.start_with?("#") }.join).not_to be_empty
    end
  end
end
