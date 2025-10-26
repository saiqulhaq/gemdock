# Research: Persistent Container Mode with Auto-Provisioning

**Phase**: 0 - Outline & Research  
**Date**: 2025-10-19  
**Feature**: 001-persistent-containers

## Overview

This document consolidates research findings for implementing persistent container mode in Gemdock. All technical unknowns from the Technical Context have been resolved through analysis of existing codebase, Docker best practices, and Ruby gem development patterns.

## Research Findings

### 1. Docker Container Persistence Patterns

**Question**: What's the best approach for keeping containers running indefinitely while maintaining responsiveness?

**Decision**: Use `sleep infinity` as the container command in Docker Compose

**Rationale**:
- `sleep infinity` is the Docker community standard for long-running containers that don't have a native service
- Uses minimal resources (process sleeps, consumes almost no CPU)
- Container remains responsive to `docker exec` commands
- Cleaner than alternatives like `tail -f /dev/null` or infinite bash loops
- Properly handles signals (SIGTERM) for graceful shutdown

**Alternatives Considered**:
- **`tail -f /dev/null`**: Works but less idiomatic, slightly more resource-intensive
- **Infinite bash loop (`while true; do sleep 1000; done`)**: More complex, unnecessary overhead
- **Custom daemon process**: Over-engineered for this use case, adds complexity
- **No command (rely on base image CMD)**: Ruby base image doesn't have long-running process

**Implementation**:
```yaml
# docker-compose-ruby-3-2-0.yml
services:
  ruby:
    image: ruby:3.2.0
    command: sleep infinity
    volumes:
      - bundler_data_ruby_3_2_0:/usr/local/bundle
    working_dir: /app
```

### 2. Container Health Check Strategy

**Question**: How should we verify container responsiveness before executing commands?

**Decision**: Use `docker exec <container> ruby --version` as health check

**Rationale**:
- Fast (<200ms typical execution time)
- Verifies both container responsiveness AND Ruby runtime availability
- Non-destructive (read-only operation)
- Returns predictable output for validation
- Catches both container failures and Ruby runtime issues

**Alternatives Considered**:
- **`docker inspect` with status check**: Only verifies container is "running", not responsive
- **Custom health check endpoint**: Over-engineered, requires additional code in container
- **`echo` command**: Faster but doesn't verify Ruby runtime is working
- **Docker HEALTHCHECK directive**: Adds complexity to compose file, requires container rebuild

**Implementation**:
```ruby
def container_healthy?(container_id)
  result = `docker exec #{container_id} ruby --version 2>&1`
  $?.success? && result.include?('ruby')
rescue => e
  false
end
```

### 3. State File Atomicity

**Question**: How to ensure state file updates are atomic to prevent corruption?

**Decision**: Use temp file + atomic rename pattern

**Rationale**:
- File rename is atomic operation on POSIX filesystems (macOS, Linux)
- Prevents partial writes if process crashes during state update
- Standard pattern for safe file updates in Ruby ecosystem
- No external dependencies required (uses stdlib File/FileUtils)
- Compatible with concurrent reads (old file remains valid until rename)

**Alternatives Considered**:
- **File locking with flock**: More complex, requires handling lock timeouts and deadlocks
- **Database (SQLite)**: Over-engineered for simple key-value storage, adds dependency
- **Direct write**: Risks corruption on crash/kill during write
- **Write-ahead log**: Too complex for this use case

**Implementation**:
```ruby
def save_state(state)
  temp_file = "#{STATE_FILE}.tmp.#{Process.pid}"
  File.write(temp_file, YAML.dump(state))
  File.rename(temp_file, STATE_FILE)
ensure
  File.delete(temp_file) if File.exist?(temp_file)
end
```

### 4. Interactive Command Detection

**Question**: How to detect when a command needs TTY allocation (interactive mode)?

**Decision**: Maintain allowlist of known interactive commands + use `-it` flags for those

**Rationale**:
- Known interactive commands (shell, bash, irb, pry, console) are finite and predictable
- More reliable than heuristics (checking stdin.isatty, etc.)
- Prevents false positives (e.g., `bundle install` with progress bars)
- Explicit is better than implicit for TTY allocation
- Easy to extend list as new interactive tools discovered

**Alternatives Considered**:
- **Check if stdin is TTY**: Doesn't work reliably in all terminal contexts
- **Always use -it**: Breaks non-interactive commands in some environments
- **User flag (--interactive)**: Adds friction, users forget to specify
- **TTY detection in container**: Requires container-side code, over-engineered

**Implementation**:
```ruby
INTERACTIVE_COMMANDS = %w[shell bash sh irb pry console rails].freeze

def interactive_command?(args)
  first_arg = args.first&.to_s&.downcase
  INTERACTIVE_COMMANDS.include?(first_arg)
end

def exec_flags(args)
  interactive_command?(args) ? '-it' : '-i'
end
```

### 5. Auto-Provisioning UX Pattern

**Question**: When should we auto-provision vs prompt user vs fail with error?

**Decision**: Three-tier approach based on configuration and context

**Rationale**:
- Balances convenience (auto-provision) with user control (confirmation prompts)
- Follows principle of least surprise: new containers get confirmation, existing containers auto-start
- Respects user configuration for opt-out scenarios
- Clear error messages when auto-provision disabled

**Implementation Tiers**:
1. **Auto-provision enabled (default)**: 
   - New container → Prompt: "No container found for Ruby X.Y.Z. Create and start? (Y/n)"
   - Stopped container → Auto-start without prompt (low risk operation)
   
2. **Auto-provision disabled**:
   - No container → Error: "Container not found. Run: gemdock provision --ruby-version X.Y.Z"
   - Stopped container → Error: "Container stopped. Run: gemdock provision start"

3. **CI/CD Mode (ephemeral)**:
   - Always use `docker run --rm`, no provisioning needed

**Alternatives Considered**:
- **Always prompt**: Friction for common case (starting stopped containers)
- **Never prompt**: Surprising behavior, users don't understand what's happening
- **Prompt with timeout**: Complex, unclear if user saw prompt before timeout

### 6. Container Lifecycle State Machine

**Question**: What are the valid state transitions for containers?

**Decision**: Three-state model with explicit transitions

**States**:
- `not_provisioned`: Container doesn't exist in Docker
- `stopped`: Container exists but not running
- `running`: Container exists and running

**Valid Transitions**:
```
not_provisioned → running (via provision or auto-provision)
running → stopped (via provision stop)
stopped → running (via provision start or auto-start)
running → not_provisioned (via provision down)
stopped → not_provisioned (via clean or provision down)
```

**Invalid Transitions** (prevented by commands):
- `not_provisioned → stopped`: Must provision directly to running state
- Direct state manipulation without Docker operations

**Rationale**:
- Matches Docker container lifecycle exactly (no abstraction mismatch)
- Simple enough to reason about (3 states, 5 transitions)
- Aligns with Docker commands (start, stop, down)
- State file always reflects actual Docker state (verified by health checks)

### 7. Version Switching Strategy

**Question**: When user switches Ruby versions with running containers, what options should we provide?

**Decision**: Interactive prompt with three options

**Options**:
1. **Stop old, start new**: Safest, minimizes resource usage (recommended)
2. **Keep both running**: Power user option, allows quick switching
3. **Cancel**: User wants to manually handle the switch

**Rationale**:
- Gives user control over resource usage
- Recommends safe option but allows power user workflows
- Prevents accidental resource bloat from forgotten containers
- Clear about resource implications of each choice

**Implementation**:
```ruby
def switch_version_prompt(old_version, new_version)
  prompt = TTY::Prompt.new
  
  prompt.select("Ruby #{old_version} container is running. How to proceed?") do |menu|
    menu.choice "Stop #{old_version}, start #{new_version} (recommended)", 1
    menu.choice "Keep both running", 2
    menu.choice "Cancel", 3
  end
end
```

**Alternatives Considered**:
- **Always stop old**: Too aggressive, breaks workflows with multiple versions
- **Always keep both**: Resource wasteful, surprising behavior
- **Binary yes/no**: Doesn't give enough control

### 8. Error Recovery Patterns

**Question**: How should we handle container failures during command execution?

**Decision**: Layered recovery with user notification

**Recovery Layers**:
1. **Health check before exec**: Prevent executing on unresponsive container
2. **Detect failure**: Catch docker exec errors
3. **Attempt restart**: Try `docker restart <container>` once
4. **Reprovision if restart fails**: Remove and recreate container
5. **Clear error if reprovision fails**: Guide user to manual intervention

**Rationale**:
- Most failures (container crash, memory issue) fixed by restart
- Restart is faster than reprovision (3-5 seconds vs 10-15 seconds)
- Reprovisioning handles corrupted container state
- Clear error messages prevent infinite retry loops
- Maintains user trust through transparency

**Implementation**:
```ruby
def execute_with_recovery(container_id, command)
  return run_command(container_id, command) if container_healthy?(container_id)
  
  logger.warn "Container unhealthy, attempting restart..."
  puts "⚠️  Container unresponsive, restarting..."
  
  if restart_container(container_id)
    return run_command(container_id, command)
  end
  
  logger.error "Restart failed, reprovisioning..."
  puts "⚠️  Restart failed, recreating container..."
  
  reprovision_container(ruby_version)
  run_command(container_id, command)
rescue => e
  raise "Container recovery failed: #{e.message}. Try: gemdock provision down && gemdock provision"
end
```

**Alternatives Considered**:
- **Fail immediately**: Poor UX, forces manual intervention for recoverable failures
- **Infinite retry**: Can loop forever, masks underlying issues
- **Always reprovision**: Slower than restart, unnecessary for transient failures

## Technology Best Practices

### Thor CLI Framework

**Best Practice**: Use `method_option` with type validation and defaults

**Source**: Thor documentation and community patterns in gems like Rails, Bundler

**Application**:
```ruby
class CLI < Thor
  desc 'exec COMMAND', 'Execute command in persistent container'
  method_option :ruby_version, 
    type: :string, 
    default: '3.2.0',
    desc: 'Ruby version to use',
    aliases: '-v'
  def exec(*args)
    # Implementation
  end
end
```

**Benefits**:
- Automatic type validation and error messages
- Built-in help generation
- Consistent option handling across commands

### tty-prompt Interactive Prompts

**Best Practice**: Use select menus for multi-choice, yes? for boolean

**Source**: tty-prompt documentation and examples

**Application**:
```ruby
require 'tty-prompt'

prompt = TTY::Prompt.new

# Multi-choice
action = prompt.select("Choose action:", %w[Start Stop Cancel])

# Boolean with default
confirm = prompt.yes?("Create container?") # defaults to no
```

**Benefits**:
- Keyboard navigation for selections
- Clear visual feedback
- Graceful degradation on non-TTY terminals

### Docker Compose V2

**Best Practice**: Use `docker compose` command (not `docker-compose`) for V2 compatibility

**Source**: Docker Compose V2 migration guide

**Application**:
```ruby
def compose_command
  # Try V2 first, fallback to V1
  `docker compose version 2>&1`.include?('version') ? 'docker compose' : 'docker-compose'
end
```

**Benefits**:
- Future-proof as V1 deprecated
- Faster performance in V2
- Better integration with Docker CLI

### YAML State Management

**Best Practice**: Use YAML.safe_load with permitted_classes to prevent object injection

**Source**: Ruby security best practices

**Application**:
```ruby
def load_state
  return default_state unless File.exist?(STATE_FILE)
  
  YAML.safe_load(
    File.read(STATE_FILE),
    permitted_classes: [Symbol, Time],
    aliases: true
  )
rescue => e
  logger.error "State file corrupted: #{e.message}"
  default_state
end
```

**Benefits**:
- Prevents arbitrary object deserialization attacks
- Handles corrupted files gracefully
- Maintains backward compatibility with Symbol keys

## Integration Patterns

### Docker API Integration

**Pattern**: Use shell commands with proper error handling (not Docker SDK)

**Rationale**:
- Docker CLI is universal and stable
- No additional gem dependencies
- Easier to debug (users can copy-paste commands)
- Simpler error messages from Docker CLI

**Implementation**:
```ruby
def docker_command(cmd, error_message: "Docker command failed")
  output = `#{cmd} 2>&1`
  raise "#{error_message}: #{output}" unless $?.success?
  output
end
```

### Logging Pattern

**Pattern**: Use Ruby stdlib Logger with rotation and structured messages

**Implementation**:
```ruby
require 'logger'

class GemDock
  def self.logger
    @logger ||= Logger.new(
      File.join(Dir.pwd, '.gemdock', 'logs', 'gemdock.log'),
      10,        # keep 10 old log files
      1024000    # rotate at 1MB
    )
  end
end
```

**Benefits**:
- Automatic rotation prevents unbounded growth
- Structured levels (debug, info, warn, error)
- Timestamp and severity in every message
- Project-specific logs (not mixed across projects)

## Validation Checklist

- ✅ All technical unknowns from Technical Context resolved
- ✅ Design decisions documented with rationale
- ✅ Alternatives considered for each decision
- ✅ Implementation examples provided
- ✅ Best practices researched and documented
- ✅ Integration patterns defined
- ✅ Security considerations addressed (YAML.safe_load)
- ✅ Error recovery strategies defined
- ✅ Performance implications considered

## Next Steps

This research phase is complete. All decisions are ready to feed into Phase 1 (Design & Contracts):
- Data model design (Container State, Configuration entities)
- API contracts for CLI commands
- Quickstart guide for developers
