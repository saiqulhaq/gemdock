# CLI Command Contracts

**Feature**: 001-persistent-containers  
**Date**: 2025-10-19  
**Type**: Command-Line Interface Specification

This document defines the contract for all Gemdock CLI commands. Each command specifies its inputs, outputs, side effects, and error conditions.

---

## Command: `gemdock exec`

**Purpose**: Execute a command in a persistent Ruby container

**Syntax**:
```bash
gemdock exec [OPTIONS] COMMAND [ARGS...]
```

**Options**:
- `--ruby-version VERSION`, `-v VERSION`: Ruby version to use (default: from .ruby-version or config)

**Arguments**:
- `COMMAND`: Command to execute (required)
- `ARGS...`: Additional arguments passed to command

**Examples**:
```bash
gemdock exec bundle install
gemdock exec --ruby-version 2.7.0 rspec spec/
gemdock exec irb
gemdock exec bash
```

**Preconditions**:
- Docker daemon is running
- Project root contains gemdock configuration

**Postconditions**:
- Command executed in container
- Container state updated (last_used timestamp)
- Operation logged to gemdock.log

**Side Effects**:
- May auto-provision container if `auto_provision: true`
- May start stopped container automatically
- Updates `$PROJECT_ROOT/.gemdock/state.yml`

**Output Format**:
```
[Ruby X.Y.Z] <command output>
```

**Exit Codes**:
- 0: Command succeeded
- 1: Docker error or container unavailable
- N: Exit code from executed command

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| Docker daemon not running | "Docker daemon not available. Is Docker running?" | Start Docker |
| Container unresponsive | "Container unhealthy, restarting..." | Auto-recovery attempted |
| No container + auto-provision disabled | "Container not found. Run: gemdock provision --ruby-version X.Y.Z" | Manual provision |
| Invalid Ruby version | "Ruby version X.Y.Z not found in Docker Hub" | Check version format |

**State Transitions**:
- `not_provisioned` → `running` (if auto-provision enabled)
- `stopped` → `running` (auto-start)
- `running` → `running` (update last_used)

---

## Command: `gemdock provision`

**Purpose**: Manage container lifecycle (start, stop, restart, down)

**Syntax**:
```bash
gemdock provision [SUBCOMMAND] [OPTIONS]
```

**Subcommands**:
- `start` (default): Start or create container
- `stop`: Stop running container
- `restart`: Restart container
- `down`: Stop and remove container

**Options**:
- `--ruby-version VERSION`, `-v VERSION`: Ruby version to manage

**Examples**:
```bash
gemdock provision                          # Start container
gemdock provision start --ruby-version 3.2.0
gemdock provision stop
gemdock provision restart
gemdock provision down                     # Requires confirmation
```

**Preconditions**:
- Docker daemon is running
- For stop/restart/down: container must exist

**Postconditions**:
- Container state matches requested subcommand
- State file updated
- Operation logged

**Side Effects**:
- Creates Docker container and volume (on first start)
- Generates docker-compose file if missing
- Updates `$PROJECT_ROOT/.gemdock/state.yml`

**Output Format**:
```
Creating Ruby X.Y.Z container...
✓ Container started (gemdock-ruby-X-Y-Z)
```

**Exit Codes**:
- 0: Operation succeeded
- 1: Docker error or operation failed

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| Stop non-existent container | "Container not provisioned" | Run `gemdock provision start` first |
| Down with confirmation denied | "Operation cancelled" | N/A |
| Docker pull failure | "Failed to pull ruby:X.Y.Z image. Check network connection" | Check connectivity |

**State Transitions**:
- `start`: `not_provisioned` → `running` OR `stopped` → `running`
- `stop`: `running` → `stopped`
- `restart`: `running` → `running` (via stopped)
- `down`: `running|stopped` → `not_provisioned`

**Confirmation Prompts**:
- `down`: "Remove container for Ruby X.Y.Z? This will stop and delete it. (y/N)"

---

## Command: `gemdock list`

**Purpose**: Show all Ruby version containers and their status

**Syntax**:
```bash
gemdock list
```

**Options**: None

**Examples**:
```bash
gemdock list
```

**Preconditions**:
- State file exists (may be empty)

**Postconditions**:
- None (read-only operation)

**Side Effects**:
- None

**Output Format**:
```
Ruby Containers:
  ✓ 3.2.0 (running)    - Last used: 2 minutes ago
  ⏸ 3.1.0 (stopped)    - Last used: 3 days ago
  ✗ 2.7.0 (not provisioned)
```

**Status Icons**:
- ✓ (green): Running
- ⏸ (yellow): Stopped
- ✗ (gray): Not provisioned

**Exit Codes**:
- 0: Success

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| Corrupted state file | "State file corrupted, recreating with defaults" | Auto-recovered |

---

## Command: `gemdock status`

**Purpose**: Show current Ruby version and container details

**Syntax**:
```bash
gemdock status
```

**Options**: None

**Examples**:
```bash
gemdock status
```

**Preconditions**:
- State file exists

**Postconditions**:
- None (read-only operation)

**Side Effects**:
- May perform health check on running container

**Output Format**:
```
Current Ruby: 3.2.0
Container: gemdock-ruby-3-2-0
Status: ✓ Running
Last Used: 2 minutes ago
Uptime: 3 hours
Volume: bundler_data_ruby_3_2_0 (1.2 GB)
```

**Exit Codes**:
- 0: Success

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| No current Ruby set | "No active Ruby version. Run: gemdock exec <command>" | Execute a command |
| Container unhealthy | "⚠️  Container unresponsive (health check failed)" | Run `gemdock provision restart` |

---

## Command: `gemdock switch`

**Purpose**: Change active Ruby version

**Syntax**:
```bash
gemdock switch VERSION
```

**Arguments**:
- `VERSION`: Ruby version to switch to (required)

**Examples**:
```bash
gemdock switch 3.2.0
gemdock switch 2.7.0
```

**Preconditions**:
- Valid Ruby version specified
- Docker daemon running

**Postconditions**:
- `current_ruby` in state file updated
- Target container running (if option selected)
- Previous container stopped (if option selected)

**Side Effects**:
- May provision new container
- May stop running container
- Updates state file

**Output Format with Interactive Prompt**:
```
Ruby 3.2.0 container is running. How to proceed?
  1) Stop 3.2.0, start 2.7.0 (recommended)
  2) Keep both running
  3) Cancel

Select [1-3]: 1

Stopping Ruby 3.2.0 container...
Creating Ruby 2.7.0 container...
✓ Switched to Ruby 2.7.0
```

**Exit Codes**:
- 0: Switch successful
- 1: Switch failed or cancelled

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| Invalid version format | "Invalid Ruby version format. Use X.Y.Z (e.g., 3.2.0)" | Correct version |
| User cancels prompt | "Operation cancelled" | N/A |

**State Transitions**:
- Old version: `running` → `stopped` (if option 1 selected)
- New version: `not_provisioned|stopped` → `running`
- Updates `current_ruby` to new version

**Interactive Prompts**:
- When switching from running container: 3 options (stop old, keep both, cancel)
- When target version not provisioned: "Create container for Ruby X.Y.Z? (Y/n)"

---

## Command: `gemdock clean`

**Purpose**: Remove stopped containers to free resources

**Syntax**:
```bash
gemdock clean [OPTIONS]
```

**Options**:
- `--all`: Stop and remove all containers (requires confirmation)

**Examples**:
```bash
gemdock clean                # Remove stopped containers
gemdock clean --all          # Stop and remove all containers
```

**Preconditions**:
- State file exists
- At least one container provisioned

**Postconditions**:
- Stopped containers removed from Docker
- State file updated (containers removed)
- Volumes preserved (data retained)

**Side Effects**:
- Removes Docker containers
- Updates `$PROJECT_ROOT/.gemdock/state.yml`
- Does NOT remove volumes (data preserved)

**Output Format**:
```
Stopped containers:
  • Ruby 3.1.0 (idle for 3 days)
  • Ruby 2.7.0 (idle for 7 days)

Remove these containers? (y/N): y

Removing containers...
✓ Removed 2 containers
Volumes preserved for quick reprovisioning.
```

**Exit Codes**:
- 0: Cleanup successful or no containers to clean
- 1: Cleanup failed

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| No stopped containers | "No stopped containers to clean" | N/A |
| User cancels prompt | "Operation cancelled" | N/A |
| Docker removal fails | "Failed to remove container X: <reason>" | Check Docker status |

**State Transitions**:
- `stopped` → `not_provisioned` (for cleaned containers)
- `running` → `not_provisioned` (only with `--all` flag)

**Confirmation Prompts**:
- Default: "Remove these containers? (y/N)"
- With `--all`: "⚠️  This will stop and remove ALL containers. Continue? (y/N)"

---

## Command: `gemdock config`

**Purpose**: Manage Gemdock configuration

**Syntax**:
```bash
gemdock config SUBCOMMAND [KEY] [VALUE]
```

**Subcommands**:
- `list`: Show all configuration values
- `get KEY`: Get specific configuration value
- `set KEY VALUE`: Set configuration value

**Examples**:
```bash
gemdock config list
gemdock config get mode
gemdock config set mode ephemeral
gemdock config set auto_provision false
gemdock config set idle_timeout_hours 48
```

**Preconditions**:
- None (creates config if missing)

**Postconditions**:
- Config file created or updated (for set)
- Configuration applied to future operations

**Side Effects**:
- Creates or updates `$PROJECT_ROOT/.gemdock/config.yml`

**Output Format**:

`list`:
```
Configuration ($PROJECT_ROOT/.gemdock/config.yml):
  mode: persistent
  auto_provision: true
  auto_cleanup_idle: false
  idle_timeout_hours: 24
  log_level: info
```

`get KEY`:
```
mode: persistent
```

`set KEY VALUE`:
```
✓ Set mode to ephemeral
```

**Exit Codes**:
- 0: Operation successful
- 1: Invalid key or value

**Error Conditions**:
| Condition | Error Message | Suggested Action |
|-----------|---------------|------------------|
| Invalid key | "Unknown configuration key: X. Valid keys: mode, auto_provision, ..." | Use valid key |
| Invalid value for enum | "Invalid value for mode: X. Must be: persistent, ephemeral" | Use valid value |
| Invalid value for boolean | "Invalid value for auto_provision: X. Must be: true, false" | Use boolean |
| Invalid value for integer | "Invalid value for idle_timeout_hours: X. Must be integer 1-720" | Use valid range |

**Valid Configuration Keys**:
| Key | Type | Valid Values | Default |
|-----|------|--------------|---------|
| mode | enum | persistent, ephemeral | persistent |
| auto_provision | boolean | true, false | true |
| auto_cleanup_idle | boolean | true, false | false |
| idle_timeout_hours | integer | 1-720 | 24 |
| default_ruby_version | string | X.Y.Z or null | null |
| log_level | enum | debug, info, warn, error | info |

---

## Global Options

All commands support these global options:

- `--help`, `-h`: Show help message
- `--version`: Show Gemdock version

**Examples**:
```bash
gemdock --help
gemdock exec --help
gemdock --version
```

---

## Exit Code Summary

| Exit Code | Meaning | Commands |
|-----------|---------|----------|
| 0 | Success | All |
| 1 | General error (Docker, invalid input, etc.) | All |
| N | Exit code from executed command | exec only |

---

## Output Conventions

### Progress Indicators

For operations taking >1 second:
```
Creating Ruby 3.2.0 container...  [⠋ spinner]
✓ Container created
```

### Ruby Version Prefix

All command output prefixed with:
```
[Ruby 3.2.0] bundle install
[Ruby 3.2.0] Using rake 13.0.6
...
```

### Status Icons

- ✓ (green checkmark): Success or running state
- ⏸ (yellow pause): Stopped state
- ✗ (gray X): Not provisioned or failure
- ⚠️  (yellow warning): Warning or requires attention

### Timestamps

Human-readable relative times:
- "2 minutes ago"
- "3 hours ago"
- "2 days ago"
- "Last week"

---

## Error Message Format

All error messages follow this structure:

```
❌ <What went wrong>

<Why it happened (if detectable)>

<Suggested fix or command to resolve>
```

**Example**:
```
❌ Container not found for Ruby 3.2.0

Auto-provisioning is disabled in config.

Run: gemdock provision --ruby-version 3.2.0
```

---

## State File Impact

This table shows which commands modify the state file:

| Command | Reads State | Writes State | State Changes |
|---------|-------------|--------------|---------------|
| exec | ✓ | ✓ | Updates last_used, may create container |
| provision start | ✓ | ✓ | Creates/starts container |
| provision stop | ✓ | ✓ | Stops container |
| provision restart | ✓ | ✓ | Updates timestamps |
| provision down | ✓ | ✓ | Removes container entry |
| list | ✓ | - | None |
| status | ✓ | - | None |
| switch | ✓ | ✓ | Updates current_ruby, may modify containers |
| clean | ✓ | ✓ | Removes container entries |
| config | - | ✓* | Creates/updates config file (*not state) |

---

## Interactive Mode Detection

Commands automatically detect interactive mode and adjust flags:

**Interactive Commands** (use `-it` flags):
- shell, bash, sh, zsh
- irb, pry
- rails console
- Any command containing "console"

**Non-Interactive Commands** (use `-i` flag only):
- bundle install
- rspec
- rake
- Any other command

**Detection Logic**:
```ruby
INTERACTIVE_COMMANDS = %w[shell bash sh zsh irb pry console rails].freeze

def interactive?(command)
  first_word = command.first&.to_s&.downcase
  INTERACTIVE_COMMANDS.any? { |cmd| first_word&.include?(cmd) }
end
```

---

## Versioning & Compatibility

**Contract Version**: 1.0.0

**Breaking Changes** require major version bump:
- Removing commands
- Changing command syntax
- Changing exit codes
- Changing output format (that may be parsed)

**Non-Breaking Changes** (minor/patch):
- Adding new commands
- Adding new options
- Improving error messages
- Adding status icons

**Backward Compatibility**:
- State file format changes handled via migration
- Old compose files continue to work
- Deprecated commands show warnings before removal
