# Data Model: Persistent Container Mode

**Feature**: 001-persistent-containers  
**Date**: 2025-10-19  
**Phase**: 1 - Design & Contracts

## Overview

This document defines the core data entities for the persistent container mode feature. These entities represent the state, configuration, and runtime information that Gemdock manages across container lifecycles.

## Entities

### 1. Container State

Represents a Docker container managed by Gemdock, tracking its lifecycle and metadata.

**Location**: `$PROJECT_ROOT/.gemdock/state.yml` (containers hash)

**Attributes**:
```yaml
containers:
  "3.2.0":                          # Ruby version (key)
    container_id: "abc123def456"    # Docker container ID (string, nullable)
    status: "running"               # Container status (enum: running|stopped|not_provisioned)
    last_used: "2025-10-19T14:30:00Z"  # ISO 8601 timestamp (string)
    volume_name: "bundler_data_ruby_3_2_0"  # Associated volume (string)
    compose_file: ".gemdock/docker-compose-ruby-3-2-0.yml"  # Compose file path (string)
    created_at: "2025-10-19T10:00:00Z"  # Initial provision time (string)
```

**Validation Rules**:
- `container_id`: Must be valid Docker container ID (64-char hex) or null if not provisioned
- `status`: Must be one of: `running`, `stopped`, `not_provisioned`
- `last_used`: Must be valid ISO 8601 timestamp, updated on every command execution
- `volume_name`: Must match format `bundler_data_ruby_X_Y_Z` where X_Y_Z is sanitized version
- `compose_file`: Must be relative path from project root
- `created_at`: Must be valid ISO 8601 timestamp, set once on first provision

**State Transitions**:
```
not_provisioned → running     (via: gemdock provision, auto-provision)
running → stopped             (via: gemdock provision stop, docker stop)
stopped → running             (via: gemdock provision start, auto-start)
running → not_provisioned     (via: gemdock provision down, gemdock clean --all)
stopped → not_provisioned     (via: gemdock clean)
```

**Invariants**:
- If `status == "not_provisioned"` then `container_id` must be null
- If `status == "running"` then `container_id` must be valid and container must exist in Docker
- `last_used` timestamp must be updated atomically with state changes
- Container state must be verified before command execution (health check)

---

### 2. Configuration

Represents user preferences for Gemdock behavior across all Ruby versions.

**Location**: `$PROJECT_ROOT/.gemdock/config.yml`

**Attributes**:
```yaml
mode: "persistent"              # Execution mode (enum: persistent|ephemeral)
auto_provision: true            # Auto-create containers (boolean, default: true)
auto_cleanup_idle: false        # Auto-clean idle containers (boolean, default: false)
idle_timeout_hours: 24          # Hours before container considered idle (integer, default: 24)
default_ruby_version: "3.2.0"   # Default Ruby version (string, nullable)
log_level: "info"               # Logging verbosity (enum: debug|info|warn|error, default: info)
```

**Validation Rules**:
- `mode`: Must be `persistent` or `ephemeral`
- `auto_provision`: Boolean only
- `auto_cleanup_idle`: Boolean only
- `idle_timeout_hours`: Integer >= 1, <= 720 (30 days max)
- `default_ruby_version`: Must match Ruby version format `X.Y.Z` or null
- `log_level`: Must be one of: `debug`, `info`, `warn`, `error`

**Default Values** (applied when config file doesn't exist):
```ruby
DEFAULT_CONFIG = {
  mode: 'persistent',
  auto_provision: true,
  auto_cleanup_idle: false,
  idle_timeout_hours: 24,
  default_ruby_version: nil,  # Will use .ruby-version file or latest
  log_level: 'info'
}
```

**Configuration Precedence**:
1. Command-line flags (e.g., `--ruby-version`)
2. Project config file (`$PROJECT_ROOT/.gemdock/config.yml`)
3. Default values

---

### 3. Ruby Version Environment

Logical grouping of all resources associated with a specific Ruby version. This is not persisted as a single entity but rather composed from multiple sources.

**Composition**:
```ruby
class RubyVersionEnvironment
  attr_reader :version, :container_state, :volume_name, :compose_file_path
  
  def initialize(version)
    @version = version                              # e.g., "3.2.0"
    @sanitized_version = sanitize_version(version)  # e.g., "3_2_0"
    @container_state = load_container_state(version)
    @volume_name = "bundler_data_ruby_#{@sanitized_version}"
    @compose_file_path = ".gemdock/docker-compose-ruby-#{@sanitized_version}.yml"
  end
  
  def container_name
    "gemdock-ruby-#{@sanitized_version}"
  end
  
  def running?
    @container_state[:status] == 'running'
  end
  
  def stopped?
    @container_state[:status] == 'stopped'
  end
  
  def provisioned?
    @container_state[:status] != 'not_provisioned'
  end
end
```

**Attributes**:
- `version`: Ruby semantic version string (e.g., "3.2.0")
- `sanitized_version`: Version with dots replaced by underscores (e.g., "3_2_0")
- `container_state`: Reference to Container State entity
- `volume_name`: Docker volume name for bundler data
- `compose_file_path`: Path to Docker Compose configuration
- `container_name`: Docker container name

**Relationships**:
- Has one Container State (identified by version)
- Has one Docker Volume (named `bundler_data_ruby_X_Y_Z`)
- Has one Docker Compose file (`.gemdock/docker-compose-ruby-X_Y_Z.yml`)
- May have one Docker Container (if provisioned)

**Isolation Boundary**:
- Each Ruby version has completely isolated gem dependencies (separate volumes)
- Container names ensure no conflicts between versions
- Compose files allow independent configuration per version

---

### 4. State File Root

Top-level structure of the state file.

**Location**: `$PROJECT_ROOT/.gemdock/state.yml`

**Structure**:
```yaml
version: "1.0.0"                # State file format version (string)
current_ruby: "3.2.0"           # Currently active Ruby version (string, nullable)
project_root: "/path/to/project"  # Absolute path to project (string)
last_updated: "2025-10-19T14:30:00Z"  # Last state modification (ISO 8601)
containers:                     # Hash of Container State entities
  "3.2.0": { ... }
  "2.7.0": { ... }
```

**Validation Rules**:
- `version`: Semantic version format, used for state file migrations
- `current_ruby`: Must be a key in `containers` hash or null
- `project_root`: Must be absolute path, verified on load
- `last_updated`: Updated atomically with any state change
- `containers`: Hash with Ruby versions as keys, Container State as values

**Atomic Update Pattern**:
```ruby
def save_state(state)
  temp_file = "#{STATE_FILE}.tmp.#{Process.pid}"
  File.write(temp_file, YAML.dump(state))
  File.rename(temp_file, STATE_FILE)  # Atomic on POSIX
ensure
  File.delete(temp_file) if File.exist?(temp_file)
end
```

---

## Entity Relationships

```
┌─────────────────────────────────────────────────────────────┐
│ State File Root ($PROJECT_ROOT/.gemdock/state.yml)         │
│                                                              │
│  current_ruby: "3.2.0"                                      │
│  containers:                                                 │
│    ├─> Container State (3.2.0) ──────┐                     │
│    ├─> Container State (3.1.0)       │                     │
│    └─> Container State (2.7.0)       │                     │
└──────────────────────────────────────┼──────────────────────┘
                                        │
                                        ▼
                    ┌────────────────────────────────────┐
                    │ Ruby Version Environment (3.2.0)   │
                    │                                     │
                    │ ┌─────────────────────────────┐    │
                    │ │ Container State             │    │
                    │ │  status: running            │    │
                    │ │  container_id: abc123       │    │
                    │ └─────────────────────────────┘    │
                    │                                     │
                    │ ┌─────────────────────────────┐    │
                    │ │ Docker Resources            │    │
                    │ │  Container: gemdock-ruby-3-2-0  │
                    │ │  Volume: bundler_data_ruby_3_2_0│
                    │ │  Compose: docker-compose-ruby-3-2-0.yml│
                    │ └─────────────────────────────┘    │
                    └────────────────────────────────────┘
                                        │
                                        │ configured by
                                        ▼
                    ┌────────────────────────────────────┐
                    │ Configuration                       │
                    │ ($PROJECT_ROOT/.gemdock/config.yml)│
                    │                                     │
                    │  mode: persistent                   │
                    │  auto_provision: true               │
                    │  default_ruby_version: "3.2.0"      │
                    └────────────────────────────────────┘
```

---

## Data Flow Examples

### Example 1: First Command Execution (Auto-Provision)

**Initial State**:
```yaml
# state.yml
version: "1.0.0"
current_ruby: null
containers: {}
```

**User runs**: `gemdock exec bundle install`

**Process**:
1. CLI determines Ruby version → "3.2.0" (from .ruby-version or default)
2. Load state → container not found, status = `not_provisioned`
3. Check config → `auto_provision: true`
4. Prompt user: "No container found for Ruby 3.2.0. Create and start? (Y/n)"
5. User confirms → Provision container
6. Update state atomically

**Final State**:
```yaml
version: "1.0.0"
current_ruby: "3.2.0"
project_root: "/Users/dev/myproject"
last_updated: "2025-10-19T14:30:00Z"
containers:
  "3.2.0":
    container_id: "abc123def456"
    status: "running"
    last_used: "2025-10-19T14:30:00Z"
    volume_name: "bundler_data_ruby_3_2_0"
    compose_file: ".gemdock/docker-compose-ruby-3-2-0.yml"
    created_at: "2025-10-19T14:30:00Z"
```

### Example 2: Version Switching with Running Container

**Initial State**:
```yaml
containers:
  "3.2.0":
    status: "running"
    container_id: "abc123"
  "2.7.0":
    status: "not_provisioned"
```

**User runs**: `gemdock switch 2.7.0`

**Process**:
1. Load state → 3.2.0 is running, 2.7.0 not provisioned
2. Prompt: "Ruby 3.2.0 container is running. How to proceed?"
   - Option 1: Stop 3.2.0, start 2.7.0 (recommended)
   - Option 2: Keep both running
   - Option 3: Cancel
3. User selects Option 1
4. Stop container 3.2.0
5. Provision container 2.7.0
6. Update state atomically

**Final State**:
```yaml
current_ruby: "2.7.0"
containers:
  "3.2.0":
    status: "stopped"
    container_id: "abc123"
  "2.7.0":
    status: "running"
    container_id: "xyz789"
    created_at: "2025-10-19T14:35:00Z"
```

---

## File Format Standards

### State File Format (YAML)

**Requirements**:
- Valid YAML 1.2
- UTF-8 encoding
- Unix line endings (LF)
- 2-space indentation
- Keys in alphabetical order (for git diff clarity)

**Example**:
```yaml
containers:
  "2.7.0":
    compose_file: ".gemdock/docker-compose-ruby-2-7-0.yml"
    container_id: "xyz789"
    created_at: "2025-10-18T10:00:00Z"
    last_used: "2025-10-19T09:00:00Z"
    status: "stopped"
    volume_name: "bundler_data_ruby_2_7_0"
  "3.2.0":
    compose_file: ".gemdock/docker-compose-ruby-3-2-0.yml"
    container_id: "abc123"
    created_at: "2025-10-19T14:30:00Z"
    last_used: "2025-10-19T14:30:00Z"
    status: "running"
    volume_name: "bundler_data_ruby_3_2_0"
current_ruby: "3.2.0"
last_updated: "2025-10-19T14:30:00Z"
project_root: "/Users/dev/myproject"
version: "1.0.0"
```

### Config File Format (YAML)

**Requirements**:
- Same YAML standards as state file
- Comments allowed for documentation
- User can manually edit safely

**Example**:
```yaml
# Gemdock Configuration
# See: https://github.com/saiqulhaq/gemdock#configuration

# Execution mode: persistent (default) or ephemeral (for CI/CD)
mode: persistent

# Automatically provision containers when missing
auto_provision: true

# Automatically clean up idle containers
auto_cleanup_idle: false

# Hours before container considered idle (default: 24)
idle_timeout_hours: 24

# Default Ruby version (overrides .ruby-version file)
# default_ruby_version: "3.2.0"

# Logging verbosity: debug, info, warn, error
log_level: info
```

---

## Migration Strategy

### State File Version Migration

When state file format changes, use version field to trigger migration:

```ruby
def load_state
  return default_state unless File.exist?(STATE_FILE)
  
  state = YAML.safe_load(File.read(STATE_FILE))
  
  case state['version']
  when '1.0.0'
    state  # Current version, no migration needed
  when nil
    migrate_from_legacy(state)  # Pre-versioning format
  else
    raise "Unsupported state file version: #{state['version']}"
  end
rescue => e
  logger.error "State file corrupted: #{e.message}"
  backup_corrupted_state
  default_state
end
```

### Backward Compatibility

- Preserve existing volume names across versions
- Support legacy compose file formats
- Gracefully handle missing fields with defaults
- Log migrations for user transparency

---

## Validation & Constraints

### Cross-Entity Constraints

1. **Container ID Consistency**: If `status == "running"`, container must exist in Docker
   ```ruby
   def validate_running_container(container_state)
     return true if container_state[:status] != 'running'
     
     container_exists?(container_state[:container_id])
   end
   ```

2. **Volume Name Consistency**: Volume name must match Ruby version
   ```ruby
   def validate_volume_name(version, volume_name)
     expected = "bundler_data_ruby_#{sanitize_version(version)}"
     volume_name == expected
   end
   ```

3. **Current Ruby Exists**: `current_ruby` must be a key in `containers` hash
   ```ruby
   def validate_current_ruby(state)
     return true if state[:current_ruby].nil?
     
     state[:containers].key?(state[:current_ruby])
   end
   ```

### Data Integrity Checks

Run on every state load:
- Verify state file is valid YAML
- Verify all required fields present
- Verify all enum values are valid
- Verify all timestamps are parseable
- Verify project_root matches current directory

Run periodically (on `gemdock status`):
- Verify container_id exists in Docker (if status == running/stopped)
- Verify volumes exist in Docker
- Verify compose files exist on filesystem
