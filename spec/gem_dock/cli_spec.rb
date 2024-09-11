# @author Saiqul Haq <saiqulhaq@gmail.com>
# frozen_string_literal: true

require "spec_helper"
require "fakefs/spec_helpers"

RSpec.describe GemDock::CLI do
  include FakeFS::SpecHelpers

  let(:cli) { described_class.new }

  before do
    FakeFS.activate!
    FileUtils.mkdir_p(Dir.pwd)
    allow(ENV).to receive(:[]).with("HOME").and_return("/home/user")
  end

  after do
    FakeFS.deactivate!
  end

  describe "#init" do
    it "creates dip.yml and docker-compose.yml" do
      cli.init
      expect(File).to exist(File.join(cli.send(:gemdock_dir), "dip.yml"))
      expect(File).to exist(File.join(cli.send(:gemdock_dir), "docker-compose.yml"))
    end
  end

  describe "#provision" do
    it "runs dip provision command" do
      expect(cli).to receive(:system).with(/DIP_FILE=.*dip provision/)
      cli.provision
    end
  end

  describe "#run" do
    it "runs dip run command" do
      expect(cli).to receive(:system).with(/DIP_FILE=.*dip run shell/)
      cli.run("shell")
    end

    it "passes multiple arguments to dip run command" do
      expect(cli).to receive(:system).with(/DIP_FILE=.*dip run bundle install/)
      cli.run("bundle", "install")
    end
  end

  describe "#execute" do
    it "runs dip run command" do
      expect(cli).to receive(:system).with(/DIP_FILE=.*dip run shell/)
      cli.execute("shell")
    end

    it "passes multiple arguments to dip run command" do
      expect(cli).to receive(:system).with(/DIP_FILE=.*dip run bundle install/)
      cli.execute("bundle", "install")
    end
  end
end
