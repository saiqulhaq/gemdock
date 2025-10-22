# frozen_string_literal: true

module IntegrationHelper
  # Generate unique container names to avoid conflicts
  def unique_container_name(ruby_version)
    sanitized = GemDock::Utils.sanitize_version(ruby_version)
    "gemdock-test-ruby-#{sanitized}-#{Time.now.to_i}-#{rand(1000)}"
  end

  # Generate unique compose file path
  def unique_compose_file(ruby_version)
    sanitized = GemDock::Utils.sanitize_version(ruby_version)
    File.join(test_gemdock_dir, "docker-compose-ruby-#{sanitized}-#{Time.now.to_i}.yml")
  end

  # Get test-specific .gemdock directory
  def test_gemdock_dir
    @test_gemdock_dir ||= begin
      dir = File.join(Dir.tmpdir, "gemdock-test-#{Process.pid}-#{Time.now.to_i}")
      FileUtils.mkdir_p(dir)
      dir
    end
  end

  # Clean up test Docker resources
  def cleanup_test_containers
    containers = `docker ps -a --filter "name=gemdock-test" --format "{{.Names}}"`.split("\n")
    containers.each do |container|
      system("docker rm -f #{container} > /dev/null 2>&1")
    end
  end

  # Clean up test volumes
  def cleanup_test_volumes
    volumes = `docker volume ls --filter "name=gemdock-test" --format "{{.Name}}"`.split("\n")
    volumes.each do |volume|
      system("docker volume rm -f #{volume} > /dev/null 2>&1")
    end
  end

  # Clean up test .gemdock directory
  def cleanup_test_directory
    FileUtils.rm_rf(test_gemdock_dir) if @test_gemdock_dir && File.exist?(@test_gemdock_dir)
    @test_gemdock_dir = nil
  end

  # Complete cleanup
  def cleanup_all_test_resources
    cleanup_test_containers
    cleanup_test_volumes
    cleanup_test_directory
  end

  # Check if Docker is available
  def docker_available?
    system("docker info > /dev/null 2>&1")
  end

  # Skip test if Docker is not available
  def skip_unless_docker_available
    skip "Docker is not available" unless docker_available?
  end

  # Wait for container to be running
  def wait_for_container(container_name, timeout: 30)
    start_time = Time.now
    loop do
      status = `docker inspect --format='{{.State.Status}}' #{container_name} 2>/dev/null`.strip
      return true if status == "running"
      
      if Time.now - start_time > timeout
        raise "Container #{container_name} did not start within #{timeout} seconds"
      end
      
      sleep 0.5
    end
  end

  # Check if container exists
  def container_exists?(container_name)
    system("docker inspect #{container_name} > /dev/null 2>&1")
  end

  # Check if volume exists
  def volume_exists?(volume_name)
    system("docker volume inspect #{volume_name} > /dev/null 2>&1")
  end

  # Get container status
  def container_status(container_name)
    `docker inspect --format='{{.State.Status}}' #{container_name} 2>/dev/null`.strip
  end

  # Execute command in container
  def exec_in_container(container_name, command)
    `docker exec #{container_name} #{command} 2>&1`
  end

  # Create a test state file
  def create_test_state_file(state_data = {})
    state_file = File.join(test_gemdock_dir, "state.yml")
    default_state = {
      "version" => 1,
      "containers" => {},
      "current_ruby" => nil
    }.merge(state_data)
    File.write(state_file, YAML.dump(default_state))
    state_file
  end

  # Create a test config file
  def create_test_config_file(config_data = {})
    config_file = File.join(test_gemdock_dir, "config.yml")
    default_config = {
      "mode" => "persistent",
      "auto_provision" => false,
      "auto_cleanup_idle" => false,
      "idle_timeout_hours" => 24,
      "default_ruby_version" => "3.2"
    }.merge(config_data)
    File.write(config_file, YAML.dump(default_config))
    config_file
  end

  # Override environment for test
  def with_test_environment
    original_home = ENV["HOME"]
    original_gemdock_dir = ENV["GEMDOCK_DIR"]
    
    begin
      ENV["GEMDOCK_DIR"] = test_gemdock_dir
      yield
    ensure
      ENV["HOME"] = original_home
      ENV["GEMDOCK_DIR"] = original_gemdock_dir
    end
  end

  # Create test managers with test directory
  def create_test_managers
    # Stub constants to use test directory
    test_state_dir = test_gemdock_dir
    test_state_file = File.join(test_state_dir, "state.yml")
    test_config_file = File.join(test_state_dir, "config.yml")
    
    # Ensure test directory exists
    FileUtils.mkdir_p(test_state_dir)
    
    # Stub StateManager constants
    stub_const("GemDock::StateManager::STATE_DIR", test_state_dir)
    stub_const("GemDock::StateManager::STATE_FILE", test_state_file)
    
    # Stub ConfigManager constants
    stub_const("GemDock::ConfigManager::CONFIG_DIR", test_state_dir)
    stub_const("GemDock::ConfigManager::CONFIG_FILE", test_config_file)
    
    # Create a test logger that doesn't write to disk
    logger = double("Logger",
      info: nil,
      warn: nil,
      error: nil,
      debug: nil
    )
    
    state_manager = GemDock::StateManager.new
    config_manager = GemDock::ConfigManager.new
    docker_command = GemDock::DockerCommand.new
    health_check = GemDock::ContainerHealthCheck.new(docker: docker_command)
    
    {
      state_manager: state_manager,
      config_manager: config_manager,
      docker_command: docker_command,
      health_check: health_check,
      logger: logger
    }
  end
end

RSpec.configure do |config|
  config.include IntegrationHelper, :integration

  # Set up before integration tests
  config.before(:each, :integration) do
    skip_unless_docker_available
    cleanup_all_test_resources
  end

  # Clean up after integration tests
  config.after(:each, :integration) do
    cleanup_all_test_resources
  end

  # Filter integration tests by tag
  config.filter_run_excluding :integration unless ENV["RUN_INTEGRATION_TESTS"]
end
