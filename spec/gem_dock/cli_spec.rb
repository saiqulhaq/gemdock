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

  describe "#exec" do
    context "when docker-compose.yml does not exist" do
      it "initializes gemdock automatically" do
        allow(cli).to receive(:default_ruby_version).and_return("3.2.2")
        allow(cli).to receive(:system).and_return(true)

        cli.exec("gem", "install", "bundler")

        expect(File).to exist(File.join(cli.send(:gemdock_dir), "docker-compose.yml"))
      end
    end

    context "when docker-compose.yml exists" do
      before do
        allow(cli).to receive(:default_ruby_version).and_return("3.2.2")
        cli.send(:initialize_gemdock)
      end

      it "runs arbitrary commands in container" do
        expect(cli).to receive(:system) do |*args|
          command = args.flatten.join(" ")
          expect(command).to include("docker")
          expect(command).to include("compose")
          expect(command).to include("run")
          expect(command).to include("gem install bundler")
        end

        cli.exec("gem", "install", "bundler")
      end

      it "opens interactive shell when 'shell' is passed" do
        expect(cli).to receive(:system) do |*args|
          command = args.flatten.join(" ")
          expect(command).to include("docker")
          expect(command).to include("compose")
          expect(command).to include("run")
          expect(command).to include("/bin/bash")
        end

        cli.exec("shell")
      end

      it "runs rspec commands" do
        expect(cli).to receive(:system) do |*args|
          command = args.flatten.join(" ")
          expect(command).to include("rspec spec/")
        end

        cli.exec("rspec", "spec/")
      end
    end

    context "when no command is provided" do
      it "prints usage information and exits" do
        expect { cli.exec }.to raise_error(SystemExit)
      end
    end
  end
end
