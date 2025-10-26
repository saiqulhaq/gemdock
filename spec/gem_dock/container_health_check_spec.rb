require "spec_helper"
require "gem_dock/container_health_check"

RSpec.describe GemDock::ContainerHealthCheck do
  let(:logger) { instance_double(GemDock::Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:docker) { instance_double(GemDock::DockerCommand) }
  let(:health_check) { described_class.new(docker: docker, logger: logger) }

  describe "#check" do
    let(:container_id) { "abc123def456" }

    context "when container is healthy" do
      before do
        # Mock inspect to show container is running
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
          .and_return({ success: true, output: "running\n", exit_code: 0 })

        # Mock ruby version check
        allow(docker).to receive(:execute)
          .with("exec #{container_id} ruby --version", timeout: 2)
          .and_return({ 
            success: true, 
            output: "ruby 3.2.0 (2022-12-25 revision a528908271) [arm64-darwin21]\n",
            exit_code: 0 
          })
      end

      it "returns healthy status" do
        status = health_check.check(container_id, use_cache: false)

        expect(status.status).to eq(:healthy)
        expect(status.healthy?).to be true
        expect(status.ruby_version).to eq("3.2.0")
        expect(status.message).to eq("Container is responsive")
      end

      it "logs health check success" do
        health_check.check(container_id, use_cache: false)

        expect(logger).to have_received(:info).with("Performing health check", container_id: container_id)
        expect(logger).to have_received(:info).with("Container healthy", hash_including(ruby_version: "3.2.0"))
      end

      it "completes in under 2 seconds", :slow do
        start_time = Time.now
        health_check.check(container_id, use_cache: false)
        duration = Time.now - start_time

        expect(duration).to be < 2
      end
    end

    context "when container is not found" do
      before do
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
          .and_return({ success: false, output: "", stderr: "No such container", exit_code: 1 })
      end

      it "returns not_found status" do
        status = health_check.check(container_id, use_cache: false)

        expect(status.status).to eq(:not_found)
        expect(status.not_found?).to be true
        expect(status.message).to eq("Container not found")
      end

      it "logs warning" do
        health_check.check(container_id, use_cache: false)

        expect(logger).to have_received(:warn).with("Container not found", hash_including(container_id: container_id))
      end
    end

    context "when container exists but is stopped" do
      before do
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
          .and_return({ success: true, output: "exited\n", exit_code: 0 })
      end

      it "returns unhealthy status" do
        status = health_check.check(container_id, use_cache: false)

        expect(status.status).to eq(:unhealthy)
        expect(status.unhealthy?).to be true
        expect(status.message).to include("Container status: exited")
      end
    end

    context "when container is unresponsive" do
      before do
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
          .and_return({ success: true, output: "running\n", exit_code: 0 })

        allow(docker).to receive(:execute)
          .with("exec #{container_id} ruby --version", timeout: 2)
          .and_return({ success: false, stderr: "cannot exec", exit_code: 126 })
      end

      it "returns unhealthy status" do
        status = health_check.check(container_id, use_cache: false)

        expect(status.status).to eq(:unhealthy)
        expect(status.message).to include("Container unresponsive")
      end
    end

    context "when health check times out" do
      before do
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
          .and_raise(GemDock::DockerCommand::TimeoutError.new("timeout"))
      end

      it "returns unhealthy status" do
        status = health_check.check(container_id, use_cache: false)

        expect(status.status).to eq(:unhealthy)
        expect(status.message).to include("Health check timed out")
      end
    end

    context "with caching" do
      before do
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
          .and_return({ success: true, output: "running\n", exit_code: 0 })

        allow(docker).to receive(:execute)
          .with("exec #{container_id} ruby --version", timeout: 2)
          .and_return({ 
            success: true, 
            output: "ruby 3.2.0 (2022-12-25 revision a528908271) [arm64-darwin21]\n",
            exit_code: 0 
          })
      end

      it "caches health check results" do
        # First call
        health_check.check(container_id, use_cache: true)
        
        # Second call should use cache
        status = health_check.check(container_id, use_cache: true)

        # Docker should only be called once
        expect(docker).to have_received(:execute).once.with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
        expect(status.healthy?).to be true
      end

      it "expires cache after TTL" do
        # First call
        first_status = health_check.check(container_id, use_cache: true)
        
        # Manually manipulate the cache timestamp to simulate expiration
        cached_status = health_check.health_cache[container_id]
        expired_status = GemDock::ContainerHealthCheck::HealthStatus.new(
          cached_status.status,
          cached_status.ruby_version,
          cached_status.message,
          Time.now - 10 # 10 seconds ago
        )
        health_check.health_cache[container_id] = expired_status
        
        # Next check should not use expired cache
        health_check.check(container_id, use_cache: true)

        # Docker should be called twice (cache expired)
        expect(docker).to have_received(:execute).twice.with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
      end

      it "can bypass cache" do
        # First call
        health_check.check(container_id, use_cache: true)
        
        # Second call without cache
        health_check.check(container_id, use_cache: false)

        # Docker should be called twice
        expect(docker).to have_received(:execute).twice.with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2)
      end
    end
  end

  describe "#check_multiple" do
    let(:container_ids) { ["container1", "container2", "container3"] }

    before do
      container_ids.each do |id|
        allow(docker).to receive(:execute)
          .with("inspect --format='{{.State.Status}}' #{id}", timeout: 2)
          .and_return({ success: true, output: "running\n", exit_code: 0 })

        allow(docker).to receive(:execute)
          .with("exec #{id} ruby --version", timeout: 2)
          .and_return({ 
            success: true, 
            output: "ruby 3.2.0 (2022-12-25 revision a528908271) [arm64-darwin21]\n",
            exit_code: 0 
          })
      end
    end

    it "checks all containers" do
      results = health_check.check_multiple(container_ids)

      expect(results.keys).to match_array(container_ids)
      expect(results.values).to all(be_a(GemDock::ContainerHealthCheck::HealthStatus))
      expect(results.values).to all(be_healthy)
    end
  end

  describe "#clear_cache" do
    let(:container_id) { "abc123" }

    before do
      allow(docker).to receive(:execute).and_return({ 
        success: true, 
        output: "running\n", 
        exit_code: 0 
      })
      
      # Populate cache
      health_check.check(container_id, use_cache: true)
    end

    it "clears cache for specific container" do
      health_check.clear_cache(container_id)
      
      # Next check should not use cache
      health_check.check(container_id, use_cache: true)

      expect(docker).to have_received(:execute).with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2).twice
    end

    it "clears all cache when no container specified" do
      health_check.clear_cache

      # Next check should not use cache
      health_check.check(container_id, use_cache: true)

      expect(docker).to have_received(:execute).with("inspect --format='{{.State.Status}}' #{container_id}", timeout: 2).twice
    end
  end

  describe "HealthStatus" do
    it "provides convenience methods" do
      healthy = described_class::HealthStatus.new(:healthy, "3.2.0", "OK", Time.now)
      unhealthy = described_class::HealthStatus.new(:unhealthy, nil, "Error", Time.now)
      not_found = described_class::HealthStatus.new(:not_found, nil, "Missing", Time.now)

      expect(healthy.healthy?).to be true
      expect(healthy.unhealthy?).to be false
      expect(healthy.not_found?).to be false

      expect(unhealthy.healthy?).to be false
      expect(unhealthy.unhealthy?).to be true
      expect(unhealthy.not_found?).to be false

      expect(not_found.healthy?).to be false
      expect(not_found.unhealthy?).to be false
      expect(not_found.not_found?).to be true
    end
  end
end
