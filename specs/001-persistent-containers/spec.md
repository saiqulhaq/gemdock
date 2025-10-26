# Feature Specification: Persistent Container Mode with Auto-Provisioning

**Feature Branch**: `001-persistent-containers`  
**Created**: 2025-10-19  
**Status**: Draft  
**Input**: User description: "Enhance Gemdock to use persistent Docker containers with auto-provisioning, supporting multiple Ruby versions with intelligent switching, container lifecycle management commands (provision, list, switch, clean), and state tracking in ${PROJECT_ROOT}/.gemdock/state.yml. Commands should use docker exec for running containers (0.3-0.6s) instead of docker run --rm (1.5-3s) to achieve 5-10x performance improvement."

## User Scenarios & Testing

### User Story 1 - Fast Command Execution with Persistent Containers (Priority: P1)

As a Ruby gem developer, I need my test suite and gem commands to execute quickly so that I can iterate rapidly during development without waiting for container startup overhead.

**Why this priority**: This is the core value proposition - 5-10x performance improvement that directly impacts daily developer productivity. Without this, the feature provides no value.

**Independent Test**: Can be fully tested by running `gemdock exec bundle install` twice and comparing execution times. First run provisions container (slower), second run uses existing container (0.3-0.6s overhead).

**Acceptance Scenarios**:

1. **Given** no containers exist, **When** user runs `gemdock exec bundle install`, **Then** system automatically provisions a container and executes command with total time under 5 seconds (excluding gem installation)
2. **Given** a container is already running for Ruby 3.2.0, **When** user runs `gemdock exec rspec spec/`, **Then** command executes with less than 0.6 seconds overhead
3. **Given** a container exists but is stopped, **When** user runs any gemdock command, **Then** system starts the container and executes command
4. **Given** user runs multiple commands in sequence, **When** comparing to ephemeral mode, **Then** persistent mode shows 5-10x performance improvement for second and subsequent commands

---

### User Story 2 - Automatic Container Provisioning (Priority: P1)

As a Ruby gem developer, I want containers to be automatically created when needed so that I don't have to manually manage Docker infrastructure before working on my gem.

**Why this priority**: Essential for the seamless user experience promised by the constitution. Users should never feel blocked by missing containers.

**Independent Test**: Can be fully tested by deleting all gemdock containers and running any `gemdock exec` command, which should complete successfully without manual intervention.

**Acceptance Scenarios**:

1. **Given** user has never used gemdock before, **When** they run their first `gemdock exec` command, **Then** system provisions container automatically with progress feedback
2. **Given** user switches to a new Ruby version, **When** no container exists for that version, **Then** system prompts "No container found for Ruby X.Y.Z. Start container? (Y/n)" and provisions on confirmation
3. **Given** auto-provisioning is disabled in config, **When** user runs command without container, **Then** system displays clear error message with instructions to run `gemdock provision`
4. **Given** container provisioning fails (e.g., network issue), **When** error occurs, **Then** system displays helpful error message with troubleshooting steps and falls back gracefully

---

### User Story 3 - Multi-Version Ruby Support with Intelligent Switching (Priority: P2)

As a gem maintainer supporting multiple Ruby versions, I need to easily switch between Ruby versions and manage their containers so that I can test my gem across all supported versions efficiently.

**Why this priority**: Critical for gem maintainers who must support multiple Ruby versions, but can be implemented after core persistent container functionality works.

**Independent Test**: Can be fully tested by running `gemdock exec --ruby-version 3.2.0 rspec` then `gemdock switch 2.7.0` and verifying state changes correctly.

**Acceptance Scenarios**:

1. **Given** user has Ruby 3.2.0 container running, **When** they run `gemdock switch 3.3.0`, **Then** system presents options: (1) Stop 3.2.0 and start 3.3.0, (2) Keep both running, (3) Cancel
2. **Given** user selects "Stop old version", **When** switch completes, **Then** old container is stopped, new container is started, and current Ruby version is updated in state
3. **Given** user has multiple containers running, **When** they run `gemdock list`, **Then** system shows all containers with status icons (✓ running, ⏸ stopped, ✗ not provisioned)
4. **Given** user runs command with `--ruby-version` flag, **When** that version's container doesn't exist, **Then** system auto-provisions it without affecting current default version

---

### User Story 4 - Container Lifecycle Management (Priority: P2)

As a developer, I need to manually control container lifecycle (start, stop, restart) so that I can manage system resources and troubleshoot container issues.

**Why this priority**: Important for resource management and troubleshooting, but developers can work without explicit lifecycle commands if auto-provisioning works well.

**Independent Test**: Can be fully tested by running `gemdock provision`, `gemdock provision stop`, and `gemdock provision restart` and verifying container state changes.

**Acceptance Scenarios**:

1. **Given** no container exists, **When** user runs `gemdock provision`, **Then** system creates and starts container for current Ruby version
2. **Given** container is running, **When** user runs `gemdock provision stop`, **Then** container is stopped gracefully
3. **Given** container is stopped, **When** user runs `gemdock provision`, **Then** existing container is started (not recreated)
4. **Given** container is running, **When** user runs `gemdock provision restart`, **Then** container is stopped and started with confirmation of uptime
5. **Given** container is running, **When** user runs `gemdock provision down`, **Then** container is stopped and removed with confirmation prompt

---

### User Story 5 - Resource Cleanup and Management (Priority: P3)

As a developer working with multiple Ruby versions, I need to clean up old containers so that I don't accumulate idle containers consuming disk space and memory.

**Why this priority**: Nice to have for resource hygiene, but not critical for daily development workflow. Can be done manually with Docker commands if needed.

**Independent Test**: Can be fully tested by creating multiple stopped containers and running `gemdock clean` to verify removal.

**Acceptance Scenarios**:

1. **Given** user has stopped containers, **When** they run `gemdock clean`, **Then** system lists stopped containers and prompts for confirmation before removal
2. **Given** user has both running and stopped containers, **When** they run `gemdock clean --all`, **Then** system stops all containers and prompts for removal confirmation
3. **Given** user has containers idle for >24 hours, **When** auto-cleanup is enabled, **Then** system notifies user about idle containers and offers to stop them
4. **Given** user runs `gemdock status`, **When** command executes, **Then** system shows container age and resource usage for cleanup decision-making

---

### User Story 6 - Container State Visibility (Priority: P2)

As a developer, I need to see which containers are running and their status so that I understand what's consuming resources and make informed decisions about container management.

**Why this priority**: Essential for transparency (Constitution Principle IV) and helps users understand what gemdock is doing with their system.

**Independent Test**: Can be fully tested by starting containers for multiple versions and running `gemdock status` and `gemdock list` to verify correct information display.

**Acceptance Scenarios**:

1. **Given** user runs `gemdock status`, **When** command executes, **Then** system shows current Ruby version, container state (running/stopped), and last used timestamp
2. **Given** user runs `gemdock list`, **When** command executes, **Then** system shows all Ruby versions with status icons and container details
3. **Given** user runs any gemdock command, **When** command executes, **Then** output is prefixed with `[Ruby X.Y.Z]` indicator
4. **Given** container provisioning or switching occurs, **When** operation is in progress, **Then** system shows progress indicators for actions taking >1 second

---

### Edge Cases

- **Container health failure**: What happens when container becomes unresponsive during command execution?
  - System should detect health check failure, log error, notify user, attempt auto-recovery by restarting container
  
- **Docker daemon down**: How does system handle Docker not running?
  - System should detect Docker unavailability, display helpful error message explaining Docker is required, provide troubleshooting link

- **Corrupted state file**: What happens when state.yml is malformed or corrupted?
  - System should detect corruption, log warning, recreate state file with defaults, notify user of reset

- **Container name conflict**: What happens if container name already exists (from manual Docker usage)?
  - System should detect conflict, offer to adopt existing container or rename/remove conflicting container

- **Disk space exhaustion**: How does system handle insufficient disk space during provisioning?
  - Docker will fail with clear error, system should detect and suggest cleanup with `gemdock clean` command

- **Multiple concurrent gemdock processes**: What happens if user runs multiple gemdock commands simultaneously?
  - Commands on same Ruby version should work (docker exec is safe), commands provisioning different versions may conflict - implement file lock

- **Ruby version doesn't exist in Docker Hub**: What happens when user specifies invalid Ruby version?
  - Docker pull will fail with clear error, system should suggest valid versions and link to Docker Hub

- **Container stopped mid-execution**: What happens if user manually stops container during command?
  - Command will fail with clear error, next gemdock command should detect stopped state and restart container

## Requirements

### Functional Requirements

- **FR-001**: System MUST use persistent containers with `docker exec` for command execution in persistent mode (default)
- **FR-002**: System MUST automatically provision containers when they don't exist, with user confirmation prompt
- **FR-003**: System MUST track container state in `$PROJECT_ROOT/.gemdock/state.yml` including: Ruby version, container ID, status (running/stopped/not_provisioned), last used timestamp
- **FR-004**: System MUST verify container health before executing commands using `docker exec <container> ruby --version`
- **FR-005**: System MUST auto-recover from unresponsive containers by reprovisioning with user notification
- **FR-006**: System MUST support both persistent mode (default) and ephemeral mode (opt-in via config) for CI/CD compatibility
- **FR-007**: System MUST provide `gemdock provision` command with subcommands: start (default), stop, restart, down
- **FR-008**: System MUST provide `gemdock list` command showing all Ruby version containers with status indicators
- **FR-009**: System MUST provide `gemdock status` command showing current Ruby version and container details
- **FR-010**: System MUST provide `gemdock switch <version>` command with interactive prompts for handling running containers
- **FR-011**: System MUST provide `gemdock clean` command for removing stopped containers with confirmation
- **FR-012**: System MUST prefix command output with `[Ruby X.Y.Z]` indicator for transparency
- **FR-013**: System MUST show progress indicators for operations taking longer than 1 second
- **FR-014**: System MUST use container naming format: `gemdock-ruby-X-Y-Z`
- **FR-015**: System MUST use volume naming format: `bundler_data_ruby_X_Y_Z` for version isolation
- **FR-016**: System MUST maintain separate Docker Compose files per Ruby version: `$PROJECT_ROOT/.gemdock/docker-compose-ruby-X-Y-Z.yml`
- **FR-017**: System MUST use `sleep infinity` command in docker-compose to keep containers running
- **FR-018**: System MUST support `--ruby-version` flag on all commands to specify Ruby version explicitly
- **FR-019**: System MUST log all Docker operations to `$PROJECT_ROOT/.gemdock/logs/gemdock.log` for debugging
- **FR-020**: System MUST detect interactive commands (shell, irb, pry, bash) and use `-it` flags with docker exec
- **FR-021**: System MUST allow configuration via `$PROJECT_ROOT/.gemdock/config.yml` with settings: mode, auto_provision, auto_cleanup_idle, idle_timeout_hours
- **FR-022**: System MUST create config file with reasonable defaults on first use if it doesn't exist
- **FR-023**: System MUST provide `gemdock config` command for managing configuration settings
- **FR-024**: System MUST execute commands with <0.6 seconds overhead when using existing running containers
- **FR-025**: System MUST provision containers within 5 seconds (excluding Docker image pull time)

### Key Entities

- **Container State**: Represents a Docker container managed by gemdock
  - Ruby version (e.g., "3.2.0")
  - Container ID (Docker container identifier)
  - Status (running, stopped, not_provisioned)
  - Last used timestamp (ISO 8601 format)
  - Related volume name
  - Related compose file path

- **Configuration**: Represents user preferences for gemdock behavior
  - Mode (persistent or ephemeral)
  - Auto-provision flag (boolean)
  - Auto-cleanup idle flag (boolean)
  - Idle timeout hours (integer)
  - Default Ruby version (string, optional)

- **Ruby Version Environment**: Logical grouping of resources for a specific Ruby version
  - Ruby version string
  - Container instance
  - Volume for bundler data
  - Docker Compose configuration file
  - Isolation boundary for gems and dependencies

## Success Criteria

### Measurable Outcomes

- **SC-001**: Command execution overhead reduced from 1.5-3 seconds (ephemeral mode) to 0.3-0.6 seconds (persistent mode) for running containers - measured by timing `gemdock exec echo "test"` before and after implementation
- **SC-002**: Container provisioning completes within 5 seconds from command initiation (excluding Docker image pull) - measured by timing first `gemdock exec` command with no container
- **SC-003**: Users can successfully switch between Ruby versions and execute commands without manual Docker intervention - measured by completing workflow: provision 3.2.0 → switch to 2.7.0 → run command → verify correct Ruby version used
- **SC-004**: Container state persists across terminal sessions and system restarts - measured by: start container → close terminal → restart system → verify container status maintained
- **SC-005**: Zero data loss when switching Ruby versions - measured by: install gems in 3.2.0 → switch to 2.7.0 → switch back to 3.2.0 → verify gems still installed
- **SC-006**: All container lifecycle operations (provision, stop, restart, clean) complete successfully 95% of the time - measured by automated test suite running 100 operations
- **SC-007**: Users can recover from container failures without losing work - measured by: manually stop container mid-execution → run next command → verify auto-recovery without data loss
- **SC-008**: Container resource usage visible to users within 1 second of requesting status - measured by timing `gemdock list` and `gemdock status` commands
- **SC-009**: System handles concurrent commands on same Ruby version without conflicts - measured by running 2-3 simultaneous `gemdock exec` commands and verifying all succeed
- **SC-010**: Performance improvement delivers 5-10x faster repeated command execution compared to ephemeral mode - measured by running 10 sequential commands and comparing total time

## Assumptions

1. **Docker availability**: Docker daemon is installed and running on user's system - this is a prerequisite for gemdock
2. **Docker Compose**: Docker Compose V2 (or docker-compose V1) is available for container orchestration
3. **Network connectivity**: Internet connection available for Docker image pulls (can fail gracefully offline with cached images)
4. **File system permissions**: User has write access to `$PROJECT_ROOT/.gemdock/` directory for config, state, and log files
5. **Ruby version format**: Ruby versions follow semantic versioning format (X.Y.Z) and match Docker Hub ruby image tags
6. **Project-specific state**: Each project has its own `.gemdock/` directory; state is isolated per project
7. **Container resource limits**: Host system has sufficient resources (CPU, memory, disk) for running 1-3 concurrent Ruby containers (typical usage)
8. **State file atomicity**: File system supports atomic renames for safe state file updates
9. **Terminal capabilities**: User terminal supports ANSI colors and Unicode for status icons (graceful degradation to plain text if not)
10. **Backward compatibility**: Existing gemdock installations can migrate to persistent mode without data loss (existing volume names maintained)

## Dependencies

- **Docker Engine**: Required for container orchestration
- **Docker Compose**: Required for multi-container configuration
- **tty-prompt gem**: For interactive prompts during version switching and cleanup
- **Ruby Logger**: For operation logging to file
- **YAML library**: For config and state file management

## Out of Scope

The following are explicitly **not** included in this feature:

- **Kubernetes support**: Only Docker and Docker Compose, no orchestration platforms
- **Remote Docker hosts**: Only local Docker daemon, no remote/cloud Docker
- **Container networking configuration**: Using default Docker networking
- **Custom Docker image building**: Only using official Ruby images from Docker Hub
- **Container resource limits**: No CPU/memory limit configuration (uses Docker defaults)
- **Log aggregation**: Simple file logging only, no log shipping or aggregation
- **Container monitoring/metrics**: Basic status only, no detailed performance metrics
- **Multi-project isolation**: Containers shared across all projects for same Ruby version
- **GUI/web interface**: CLI only, no graphical interface
- **Container scheduling**: No cron-like scheduled operations
- **Backup/restore**: No built-in backup of state or container data
- **Container migration**: No export/import of containers between machines
- **Windows Container support**: Docker for Mac/Linux only
- **ARM architecture optimization**: Works on ARM but no special optimizations

## Migration Path

For users upgrading from ephemeral mode (current implementation):

1. **Automatic detection**: On first command after upgrade, detect if `$PROJECT_ROOT/.gemdock/state.yml` exists
2. **Volume preservation**: Existing volumes (`bundler_data_ruby_X_Y_Z`) are automatically adopted by persistent containers
3. **Opt-out available**: Users can set `mode: ephemeral` in config to maintain current behavior
4. **No breaking changes**: Existing `--ruby-version` flags and compose files continue to work
5. **Progressive enhancement**: Users benefit from performance improvement immediately without configuration changes
