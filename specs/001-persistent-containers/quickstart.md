# Quickstart Guide: Persistent Container Mode

**Feature**: 001-persistent-containers  
**Audience**: Developers implementing this feature  
**Last Updated**: 2025-10-19

## Overview

This quickstart guide helps developers understand and implement the persistent container mode feature. It covers the architecture, key components, implementation patterns, and testing strategies.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Command                              │
│                   gemdock exec bundle install                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CLI (lib/gem_dock/cli.rb)                   │
│  • Parse command and options                                     │
│  • Determine Ruby version                                        │
│  • Delegate to ContainerManager                                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│            ContainerManager (lib/gem_dock/container_manager.rb)  │
│  • Check container state                                         │
│  • Execute health checks                                         │
│  • Run docker exec command                                       │
│  • Handle auto-provisioning                                      │
└──────┬─────────────────┬──────────────────┬────────────────────┘
       │                 │                  │
       ▼                 ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ StateManager │  │ConfigManager │  │    Logger    │
│              │  │              │  │              │
│ • Load state │  │ • Load config│  │ • Log ops    │
│ • Save state │  │ • Validate   │  │ • Rotate logs│
│ • Validate   │  │ • Defaults   │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
       │                 │                  │
       ▼                 ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                   File System & Docker                           │
│  • $PROJECT_ROOT/.gemdock/state.yml                             │
│  • $PROJECT_ROOT/.gemdock/config.yml                            │
│  • $PROJECT_ROOT/.gemdock/docker-compose-ruby-*.yml             │
│  • Docker containers, volumes, images                            │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. CLI (Thor Framework)

**Location**: `lib/gem_dock/cli.rb`

**Responsibilities**:
- Parse command-line arguments using Thor
- Validate input (Ruby version format, command presence)
- Coordinate between managers
- Handle user prompts (via tty-prompt)
- Display formatted output

**Key Methods**:
```ruby
class CLI < Thor
  desc 'exec COMMAND', 'Execute command in persistent container'
  method_option :ruby_version, type: :string, aliases: '-v'
  def exec(*args)
    ruby_version = determine_ruby_version(options[:ruby_version])
    container_manager.execute(ruby_version, args)
  end
  
  desc 'provision SUBCOMMAND', 'Manage container lifecycle'
  method_option :ruby_version, type: :string, aliases: '-v'
  def provision(subcommand = 'start')
    # Implementation
  end
end
```

### 2. ContainerManager

**Location**: `lib/gem_dock/container_manager.rb`

**Responsibilities**:
- Container lifecycle operations (create, start, stop, remove)
- Health checks before execution
- Docker command execution
- Auto-provisioning logic
- Error recovery

**Key Methods**:
```ruby
class ContainerManager
  def execute(ruby_version, command)
    ensure_container_available(ruby_version)
    verify_health(ruby_version)
    run_command_in_container(ruby_version, command)
  end
  
  def provision(ruby_version, action: :start)
    case action
    when :start
      start_or_create_container(ruby_version)
    when :stop
      stop_container(ruby_version)
    when :restart
      restart_container(ruby_version)
    when :down
      remove_container(ruby_version)
    end
  end
  
  private
  
  def ensure_container_available(ruby_version)
    state = state_manager.container_state(ruby_version)
    
    case state[:status]
    when 'not_provisioned'
      handle_not_provisioned(ruby_version)
    when 'stopped'
      start_container(ruby_version)
    when 'running'
      # Ready to use
    end
  end
  
  def verify_health(ruby_version)
    container_id = state_manager.container_id(ruby_version)
    result = `docker exec #{container_id} ruby --version 2>&1`
    
    unless $?.success? && result.include?('ruby')
      logger.warn "Container unhealthy, attempting recovery..."
      recover_unhealthy_container(ruby_version)
    end
  end
end
```

### 3. StateManager

**Location**: `lib/gem_dock/state_manager.rb`

**Responsibilities**:
- Load/save state file
- Validate state structure
- Atomic state updates
- State migrations

**Key Methods**:
```ruby
class StateManager
  STATE_FILE = File.join(Dir.pwd, '.gemdock', 'state.yml')
  
  def initialize
    @state = load_state
  end
  
  def container_state(ruby_version)
    @state[:containers][ruby_version] || default_container_state
  end
  
  def update_container(ruby_version, updates)
    @state[:containers][ruby_version] ||= default_container_state
    @state[:containers][ruby_version].merge!(updates)
    @state[:last_updated] = Time.now.utc.iso8601
    save_state
  end
  
  def container_running?(ruby_version)
    container_state(ruby_version)[:status] == 'running'
  end
  
  private
  
  def load_state
    return default_state unless File.exist?(STATE_FILE)
    
    YAML.safe_load(
      File.read(STATE_FILE),
      permitted_classes: [Symbol, Time],
      aliases: true
    )
  rescue => e
    logger.error "State file corrupted: #{e.message}"
    backup_corrupted_state
    default_state
  end
  
  def save_state
    ensure_gemdock_directory
    temp_file = "#{STATE_FILE}.tmp.#{Process.pid}"
    File.write(temp_file, YAML.dump(@state))
    File.rename(temp_file, STATE_FILE)
  ensure
    File.delete(temp_file) if File.exist?(temp_file)
  end
  
  def default_state
    {
      version: '1.0.0',
      current_ruby: nil,
      project_root: Dir.pwd,
      last_updated: Time.now.utc.iso8601,
      containers: {}
    }
  end
end
```

### 4. ConfigManager

**Location**: `lib/gem_dock/config_manager.rb`

**Responsibilities**:
- Load/save configuration
- Provide configuration values with defaults
- Validate configuration updates

**Key Methods**:
```ruby
class ConfigManager
  CONFIG_FILE = File.join(Dir.pwd, '.gemdock', 'config.yml')
  
  DEFAULT_CONFIG = {
    mode: 'persistent',
    auto_provision: true,
    auto_cleanup_idle: false,
    idle_timeout_hours: 24,
    default_ruby_version: nil,
    log_level: 'info'
  }.freeze
  
  def initialize
    @config = load_config
  end
  
  def persistent_mode?
    @config[:mode] == 'persistent'
  end
  
  def ephemeral_mode?
    @config[:mode] == 'ephemeral'
  end
  
  def auto_provision?
    @config[:auto_provision]
  end
  
  def set(key, value)
    validate_config_key(key, value)
    @config[key.to_sym] = value
    save_config
  end
  
  private
  
  def load_config
    return DEFAULT_CONFIG.dup unless File.exist?(CONFIG_FILE)
    
    user_config = YAML.safe_load(File.read(CONFIG_FILE), symbolize_names: true)
    DEFAULT_CONFIG.merge(user_config)
  rescue => e
    logger.warn "Config file error: #{e.message}, using defaults"
    DEFAULT_CONFIG.dup
  end
end
```

## Implementation Workflow

### Step 1: Set Up Project Structure

```bash
# Create new module files
touch lib/gem_dock/state_manager.rb
touch lib/gem_dock/config_manager.rb
touch lib/gem_dock/container_manager.rb
touch lib/gem_dock/logger.rb

# Create test files
touch spec/gem_dock/state_manager_spec.rb
touch spec/gem_dock/config_manager_spec.rb
touch spec/gem_dock/container_manager_spec.rb
mkdir -p spec/gem_dock/integration
touch spec/gem_dock/integration/persistent_mode_spec.rb
```

### Step 2: Implement StateManager

Focus on:
1. State file loading with YAML.safe_load
2. Atomic saves using temp file + rename
3. Validation and defaults
4. State migrations

**Test Coverage**:
- Load valid state file
- Load corrupted state file (should use defaults)
- Atomic save (crash during write)
- Container state CRUD operations
- State migrations from legacy format

### Step 3: Implement ConfigManager

Focus on:
1. Configuration loading with defaults
2. Configuration validation
3. Type checking for each config key

**Test Coverage**:
- Load with no config file (should use defaults)
- Load with partial config (should merge with defaults)
- Set valid configuration values
- Reject invalid configuration values

### Step 4: Implement ContainerManager

Focus on:
1. Docker command execution
2. Health checks
3. Auto-provisioning with prompts
4. Error recovery

**Test Coverage**:
- Execute command in running container
- Auto-provision new container
- Auto-start stopped container
- Health check failure and recovery
- Interactive command detection

### Step 5: Update CLI

Focus on:
1. Add new commands (provision, list, status, switch, clean, config)
2. Update exec command to use ContainerManager
3. Add tty-prompt for interactive prompts
4. Format output with status icons

**Test Coverage**:
- All command variations
- Option parsing
- Error handling
- Interactive prompts (mocked)

### Step 6: Integration Testing

Focus on:
1. End-to-end workflows
2. Actual Docker operations
3. State persistence across commands

**Test Coverage**:
- First-time user flow (auto-provision)
- Version switching
- Container lifecycle (start/stop/restart/down)
- Error recovery scenarios

## Common Patterns

### Pattern 1: Atomic State Updates

Always use this pattern when updating state:

```ruby
def update_state_example
  state_manager.update_container(ruby_version, {
    status: 'running',
    container_id: container_id,
    last_used: Time.now.utc.iso8601
  })
end
```

### Pattern 2: Health Check Before Execution

Always verify container health before executing commands:

```ruby
def execute_with_health_check(ruby_version, command)
  container_id = state_manager.container_id(ruby_version)
  
  unless container_healthy?(container_id)
    logger.warn "Container unhealthy, recovering..."
    recover_container(ruby_version)
  end
  
  run_docker_exec(container_id, command)
end

def container_healthy?(container_id)
  result = `docker exec #{container_id} ruby --version 2>&1`
  $?.success? && result.include?('ruby')
rescue
  false
end
```

### Pattern 3: User Confirmation Prompts

Use tty-prompt for consistent interactive prompts:

```ruby
def prompt_for_provision(ruby_version)
  return false unless config_manager.auto_provision?
  
  prompt = TTY::Prompt.new
  prompt.yes?("No container found for Ruby #{ruby_version}. Create and start?")
end

def prompt_for_cleanup(containers)
  prompt = TTY::Prompt.new
  
  puts "Stopped containers:"
  containers.each do |version, state|
    puts "  • Ruby #{version} (idle for #{idle_time(state)})"
  end
  
  prompt.yes?("Remove these containers?")
end
```

### Pattern 4: Error Handling with Recovery

Always provide recovery suggestions in errors:

```ruby
def execute_with_recovery(ruby_version, command)
  run_command(ruby_version, command)
rescue ContainerNotFoundError
  if config_manager.auto_provision?
    provision_and_retry(ruby_version, command)
  else
    raise UserError, <<~MSG
      Container not found for Ruby #{ruby_version}
      
      Auto-provisioning is disabled in config.
      
      Run: gemdock provision --ruby-version #{ruby_version}
    MSG
  end
rescue DockerDaemonError
  raise UserError, <<~MSG
    Docker daemon not available. Is Docker running?
    
    Start Docker and try again.
  MSG
end
```

## Testing Strategy

### Unit Tests (Fast, Isolated)

**Location**: `spec/gem_dock/*_spec.rb`

**Focus**:
- Individual methods in each manager
- Mocked filesystem and Docker commands
- Edge cases and error conditions

**Example**:
```ruby
RSpec.describe GemDock::StateManager do
  let(:state_manager) { described_class.new }
  
  before do
    FakeFS.activate!
    FileUtils.mkdir_p('.gemdock')
  end
  
  after { FakeFS.deactivate! }
  
  describe '#container_state' do
    context 'when container exists' do
      before do
        File.write('.gemdock/state.yml', YAML.dump({
          containers: { '3.2.0' => { status: 'running' } }
        }))
      end
      
      it 'returns container state' do
        state = state_manager.container_state('3.2.0')
        expect(state[:status]).to eq('running')
      end
    end
    
    context 'when container does not exist' do
      it 'returns default state' do
        state = state_manager.container_state('3.2.0')
        expect(state[:status]).to eq('not_provisioned')
      end
    end
  end
end
```

### Integration Tests (Slower, Real Docker)

**Location**: `spec/gem_dock/integration/persistent_mode_spec.rb`

**Focus**:
- End-to-end workflows
- Actual Docker operations
- State persistence

**Example**:
```ruby
RSpec.describe 'Persistent Mode Integration', :integration do
  before(:all) do
    # Clean up any existing test containers
    `docker stop gemdock-ruby-3-2-0 2>/dev/null`
    `docker rm gemdock-ruby-3-2-0 2>/dev/null`
  end
  
  it 'executes commands in persistent container' do
    # First execution should auto-provision
    output = `gemdock exec --ruby-version 3.2.0 ruby --version`
    expect(output).to include('ruby 3.2.0')
    expect($?).to be_success
    
    # Second execution should reuse container (faster)
    start_time = Time.now
    output = `gemdock exec --ruby-version 3.2.0 echo "test"`
    duration = Time.now - start_time
    
    expect(output).to include('[Ruby 3.2.0] test')
    expect(duration).to be < 1.0  # Should be very fast
  end
  
  it 'persists state across command invocations' do
    `gemdock exec --ruby-version 3.2.0 bundle install`
    
    state = YAML.load_file('.gemdock/state.yml')
    expect(state['containers']['3.2.0']['status']).to eq('running')
    expect(state['containers']['3.2.0']['container_id']).not_to be_nil
  end
end
```

### Performance Tests

**Focus**:
- Command execution overhead
- State file operations
- Health check timing

**Example**:
```ruby
RSpec.describe 'Performance', :performance do
  it 'executes commands with <0.6s overhead' do
    # Ensure container is running
    `gemdock provision --ruby-version 3.2.0`
    
    # Measure pure overhead (echo is instant)
    overhead_times = 10.times.map do
      start_time = Time.now
      `gemdock exec --ruby-version 3.2.0 echo "test"`
      Time.now - start_time
    end
    
    avg_overhead = overhead_times.sum / overhead_times.size
    expect(avg_overhead).to be < 0.6
  end
end
```

## Debugging Tips

### Enable Verbose Logging

```bash
gemdock config set log_level debug
cat .gemdock/logs/gemdock.log
```

### Inspect State File

```bash
cat .gemdock/state.yml
```

### Check Docker Container Status

```bash
docker ps -a | grep gemdock
docker logs gemdock-ruby-3-2-0
```

### Verify Health Check

```bash
docker exec gemdock-ruby-3-2-0 ruby --version
```

### Reset Everything

```bash
gemdock clean --all
rm -rf .gemdock
```

## Performance Optimization

### 1. Cache Docker Commands

Don't shell out repeatedly for the same info:

```ruby
def docker_compose_command
  @docker_compose_command ||= begin
    `docker compose version 2>&1`.include?('version') ? 'docker compose' : 'docker-compose'
  end
end
```

### 2. Minimize State File Operations

Batch updates when possible:

```ruby
# Bad: Multiple saves
state_manager.update_container(version, status: 'running')
state_manager.update_container(version, container_id: id)
state_manager.update_container(version, last_used: time)

# Good: Single save
state_manager.update_container(version, {
  status: 'running',
  container_id: id,
  last_used: time
})
```

### 3. Lazy Load Configuration

Don't load config on every method call:

```ruby
class ContainerManager
  def config
    @config ||= ConfigManager.new
  end
  
  def state
    @state ||= StateManager.new
  end
end
```

## Next Steps

After completing the implementation:

1. **Run full test suite**: `bundle exec rspec`
2. **Test integration with real Docker**: `bundle exec rspec --tag integration`
3. **Performance testing**: Verify <0.6s overhead for running containers
4. **Documentation**: Update README.md and DESIGN.md
5. **Changelog**: Document all new features and breaking changes

## Resources

- **Thor CLI Framework**: https://github.com/rails/thor
- **tty-prompt**: https://github.com/piotrmurach/tty-prompt
- **Docker Compose**: https://docs.docker.com/compose/
- **YAML.safe_load**: https://ruby-doc.org/stdlib-3.0.0/libdoc/psych/rdoc/Psych.html#method-c-safe_load

---

**Ready to start implementing?** Begin with StateManager (simplest component) and work your way up to ContainerManager (most complex).
