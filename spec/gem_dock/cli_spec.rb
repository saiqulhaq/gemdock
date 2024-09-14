# @author Saiqul Haq <saiqulhaq@gmail.com>
# frozen_string_literal: true

require "spec_helper"
require "fakefs/spec_helpers"

RSpec.describe GemDock::CLI do
  include FakeFS::SpecHelpers

  let(:cli) do
    described_class.new
  end

  before do
    FakeFS.activate!
    FileUtils.mkdir_p(Dir.pwd)
    allow(ENV).to receive(:[]).with("THOR_SHELL").and_return(nil)
    allow(ENV).to receive(:[]).with("HOME").and_return("/home/user")
  end

  after do
    FakeFS.deactivate!
  end

  describe "#init" do
    it "creates dip.yml and docker-compose.yml" do
      allow(cli).to receive(:default_ruby_version).and_return("3.2.2")

      cli.init
      expect(File).to exist(File.join(cli.send(:gemdock_dir), "dip.yml"))
      expect(File).to exist(File.join(cli.send(:gemdock_dir), "docker-compose.yml"))
    end
  end

  describe "#update" do
    it "updates docker-compose.yml file" do
      allow(cli).to receive(:default_ruby_version).and_return(GemDock::DEFAULT_RUBY_VERSION)
      cli.init

      allow(cli).to receive(:default_ruby_version).and_return("2.7.0")
      cli.update

      expect(File).to exist(File.join(cli.send(:gemdock_dir), "docker-compose.yml"))
      # docker-compose.yml should contain the updated ruby version
      expect(File.read(File.join(cli.send(:gemdock_dir), "docker-compose.yml"))).to include("2.7.0")
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
end
