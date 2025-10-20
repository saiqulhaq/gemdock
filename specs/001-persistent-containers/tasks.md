# Implementation Tasks: Persistent Container Mode

**Feature**: 001-persistent-containers  
**Branch**: `001-persistent-containers`  
**Date**: 2025-10-19  
**Status**: Ready for Implementation

Generated from design artifacts: plan.md, data-model.md, quickstart.md, contracts/cli-commands.md, research.md

## Task Overview

**Total Tasks**: 47  
**Estimated Duration**: 8-10 development days  
**Dependencies**: 6 dependency chains identified  

## Task Categories

- 🔧 **Foundation** (7 tasks): Core managers and infrastructure
- 📁 **Data Layer** (8 tasks): State and configuration management  
- 🐳 **Container** (12 tasks): Docker container lifecycle operations
- 🖥️ **CLI** (10 tasks): Command-line interface enhancements
- 🧪 **Testing** (8 tasks): Unit, integration, and performance tests
- 📚 **Documentation** (2 tasks): User-facing documentation

---

## Phase 1: Foundation & Data Layer (Days 1-2)

### Foundation Tasks

#### T001 🔧 Create Project Structure
**Priority**: P0 (Blocking)  
**Dependencies**: None  
**Estimated Time**: 30 minutes

**Description**: Set up the basic file structure for new components

**Acceptance Criteria**:
- [x] Create `lib/gem_dock/state_manager.rb`
- [x] Create `lib/gem_dock/config_manager.rb` 
- [x] Create `lib/gem_dock/container_manager.rb`
- [x] Create `lib/gem_dock/logger.rb`
- [ ] Create corresponding test files in `spec/gem_dock/`
- [ ] Create `spec/gem_dock/integration/` directory
- [ ] All files have proper Ruby module structure and copyright headers

**Implementation Notes**:
- Follow existing file naming patterns
- Include proper module nesting (`module GemDock`)
- Add basic class structure with initialize methods

---

#### T002 🔧 Implement Logger Module
**Priority**: P0 (Blocking)  
**Dependencies**: T001  
**Estimated Time**: 45 minutes

**Description**: Create centralized logging with rotation and structured output

**Acceptance Criteria**:
- [ ] Logger class with configurable levels (debug, info, warn, error)
- [ ] Log file rotation at 10MB
- [ ] Structured log format with timestamps
- [ ] Project-specific log location: `$PROJECT_ROOT/.gemdock/logs/gemdock.log`
- [ ] Thread-safe logging operations

**Implementation Notes**:
```ruby
# Expected API
logger = GemDock::Logger.new
logger.info("Container started", ruby_version: "3.2.0", container_id: "abc123")
logger.warn("Health check failed", ruby_version: "3.2.0", attempt: 2)
```

---

#### T003 📁 Implement ConfigManager Foundation
**Priority**: P0 (Blocking)  
**Dependencies**: T001, T002  
**Estimated Time**: 1 hour

**Description**: Core configuration management with YAML persistence

**Acceptance Criteria**:
- [ ] Load configuration from `$PROJECT_ROOT/.gemdock/config.yml`
- [ ] Merge with default values for missing keys
- [ ] Validate configuration values (type checking, enum validation)
- [ ] Atomic save with temp file + rename pattern
- [ ] Handle missing/corrupted config files gracefully

**Implementation Notes**:
- Use constants for default configuration
- Implement validation for each config key type
- Return frozen hash to prevent external mutation

---

#### T004 📁 Implement StateManager Foundation  
**Priority**: P0 (Blocking)  
**Dependencies**: T001, T002  
**Estimated Time**: 1.5 hours

**Description**: Container state persistence with atomic updates

**Acceptance Criteria**:
- [ ] Load state from `$PROJECT_ROOT/.gemdock/state.yml`
- [ ] Atomic state updates using temp file + rename
- [ ] State validation on load (schema compliance)
- [ ] Handle corrupted state files with backup and defaults
- [ ] State file version tracking for migrations

**Implementation Notes**:
- Implement state corruption recovery
- Use Process.pid for unique temp filenames
- Validate container_id format and status enum values

---

#### T005 📁 Define Data Models and Validation
**Priority**: P1 (Important)  
**Dependencies**: T003, T004  
**Estimated Time**: 1 hour

**Description**: Implement data validation rules from data-model.md specification

**Acceptance Criteria**:
- [ ] Container state validation (status enum, timestamps, container_id format)
- [ ] Configuration validation (mode enum, numeric ranges, Ruby version format)
- [ ] Cross-entity validation (current_ruby exists in containers hash)
- [ ] State transition validation (valid state machine transitions)
- [ ] Error messages with correction suggestions

**Implementation Notes**:
- Create validation mixins for reuse across managers
- Use Ruby's built-in validation patterns (respond_to?, is_a?, match?)

---

#### T006 📁 Implement State Migration System
**Priority**: P2 (Nice to have)  
**Dependencies**: T004, T005  
**Estimated Time**: 45 minutes

**Description**: Handle state file format migrations for backward compatibility

**Acceptance Criteria**:
- [ ] Detect state file version from `version` field
- [ ] Migrate legacy format (pre-versioning) to v1.0.0
- [ ] Backup original state file before migration
- [ ] Log migration operations
- [ ] Fail gracefully on unsupported versions

**Implementation Notes**:
- Start with v1.0.0 format
- Create migration framework for future versions

---

#### T007 🔧 Create Shared Utilities
**Priority**: P1 (Important)  
**Dependencies**: T001  
**Estimated Time**: 30 minutes

**Description**: Common utility functions used across components

**Acceptance Criteria**:
- [ ] Ruby version format validation (`/\A\d+\.\d+\.\d+\z/`)
- [ ] Version sanitization for Docker names (dots to underscores)
- [ ] Docker container name generation
- [ ] File path utilities for `.gemdock` directory
- [ ] Timestamp utilities (ISO 8601 format)

**Implementation Notes**:
- Create `lib/gem_dock/utils.rb` module
- Include utilities as module methods

---

## Phase 2: Container Management (Days 3-4)

### Container Infrastructure

#### T008 🐳 Implement Docker Command Wrapper
**Priority**: P0 (Blocking)  
**Dependencies**: T002  
**Estimated Time**: 1 hour

**Description**: Safe Docker command execution with error handling

**Acceptance Criteria**:
- [ ] Execute Docker commands with proper error capture
- [ ] Parse command output and exit codes
- [ ] Timeout protection for long-running commands
- [ ] Structured error messages with debugging info
- [ ] Command logging for troubleshooting

**Implementation Notes**:
```ruby
# Expected API
result = docker_command("exec container_id ruby --version")
# Returns: { success: true, output: "ruby 3.2.0...", exit_code: 0 }
```

---

#### T009 🐳 Implement Container Health Checks
**Priority**: P0 (Blocking)  
**Dependencies**: T008  
**Estimated Time**: 45 minutes

**Description**: Verify container responsiveness before command execution

**Acceptance Criteria**:
- [ ] Health check using `docker exec <container> ruby --version`
- [ ] Complete health check in <2 seconds
- [ ] Distinguish between container not found vs unresponsive
- [ ] Return structured health status (healthy/unhealthy/not_found)
- [ ] Log health check results

**Implementation Notes**:
- Cache health check results for 30 seconds to avoid repeated calls
- Include Ruby version verification in health check

---

#### T010 🐳 Implement Container Lifecycle Operations
**Priority**: P0 (Blocking)  
**Dependencies**: T008, T004  
**Estimated Time**: 2 hours

**Description**: Core container start/stop/restart operations

**Acceptance Criteria**:
- [ ] Start containers using Docker Compose
- [ ] Stop containers gracefully with timeout
- [ ] Restart containers with health verification
- [ ] Remove containers and associated volumes
- [ ] Update state file after each operation

**Implementation Notes**:
- Use `docker compose up -d` for starting
- Implement 30-second timeout for graceful shutdown
- Verify operations succeeded before updating state

---

#### T011 🐳 Implement Container Provisioning
**Priority**: P0 (Blocking)  
**Dependencies**: T010, T003  
**Estimated Time**: 1.5 hours

**Description**: Create and configure new containers with Docker Compose

**Acceptance Criteria**:
- [ ] Generate Docker Compose file for Ruby version
- [ ] Create container with `sleep infinity` command
- [ ] Set up named volume for bundler data
- [ ] Configure working directory and environment
- [ ] Verify successful provisioning with health check

**Implementation Notes**:
- Generate compose file from template in `docker_compose_generator.rb`
- Use naming pattern: `gemdock-ruby-X-Y-Z`
- Mount project directory as `/app` in container

---

#### T012 🐳 Implement Auto-Provisioning Logic
**Priority**: P1 (Important)  
**Dependencies**: T011, T003  
**Estimated Time**: 1 hour

**Description**: Intelligent container provisioning with user prompts

**Acceptance Criteria**:
- [ ] Detect when container needs provisioning
- [ ] Prompt user for confirmation (respects `auto_provision` config)
- [ ] Auto-start stopped containers without prompting
- [ ] Handle CI/CD mode (no prompts, use ephemeral containers)
- [ ] Progress indicators for operations >1 second

**Implementation Notes**:
- Use tty-prompt for user interaction
- Check TTY availability before prompting
- Different behavior for new vs stopped containers

---

#### T013 🐳 Implement Container Command Execution
**Priority**: P0 (Blocking)  
**Dependencies**: T009, T012  
**Estimated Time**: 1.5 hours

**Description**: Execute commands in persistent containers using docker exec

**Acceptance Criteria**:
- [ ] Use `docker exec` for command execution in running containers
- [ ] Detect interactive commands and allocate TTY appropriately
- [ ] Stream command output in real-time
- [ ] Preserve exit codes from container commands
- [ ] Update container last_used timestamp

**Implementation Notes**:
- Interactive commands: shell, bash, irb, pry, console, rails
- Use `-it` for interactive, `-i` for non-interactive commands
- Handle large output streams efficiently

---

#### T014 🐳 Implement Error Recovery System
**Priority**: P1 (Important)  
**Dependencies**: T013  
**Estimated Time**: 1 hour

**Description**: Layered recovery for container failures

**Acceptance Criteria**:
- [ ] Detect container failures during command execution
- [ ] Attempt container restart for recoverable failures
- [ ] Reprovision container if restart fails
- [ ] Clear error state with user guidance if all recovery fails
- [ ] Log recovery attempts and outcomes

**Implementation Notes**:
- Recovery layers: health check → restart → reprovision → manual intervention
- Provide clear error messages with suggested actions
- Avoid infinite retry loops

---

#### T015 🐳 Implement Multi-Version Container Management
**Priority**: P1 (Important)  
**Dependencies**: T010, T004  
**Estimated Time**: 1 hour

**Description**: Manage multiple Ruby version containers simultaneously

**Acceptance Criteria**:
- [ ] Track multiple container states in single state file
- [ ] Isolate containers with unique names and volumes
- [ ] Support switching between versions
- [ ] Handle resource management (stop old when starting new)
- [ ] Prevent naming conflicts between versions

**Implementation Notes**:
- Container isolation using sanitized version strings
- Volume isolation: `bundler_data_ruby_X_Y_Z`

---

#### T016 🐳 Implement Version Switching Logic
**Priority**: P1 (Important)  
**Dependencies**: T015  
**Estimated Time**: 1 hour

**Description**: Interactive version switching with resource management

**Acceptance Criteria**:
- [ ] Prompt user when switching from running container
- [ ] Options: stop old + start new, keep both, cancel
- [ ] Update current_ruby in state file
- [ ] Provide resource usage warnings
- [ ] Handle switching to non-provisioned versions

**Implementation Notes**:
- Use tty-prompt for selection menu
- Show resource implications of each choice
- Default to resource-efficient option (stop old)

---

#### T017 🐳 Implement Container Cleanup Operations
**Priority**: P2 (Nice to have)  
**Dependencies**: T015  
**Estimated Time**: 45 minutes

**Description**: Remove unused containers and volumes

**Acceptance Criteria**:
- [ ] Identify idle containers (configurable timeout)
- [ ] Remove stopped containers with confirmation
- [ ] Clean up associated volumes and compose files
- [ ] Support force cleanup without confirmation
- [ ] Update state file after cleanup

**Implementation Notes**:
- Default idle timeout: 24 hours
- Preserve running containers from cleanup
- Option for cleaning all containers: `--all`

---

#### T018 🐳 Implement Container Inspection
**Priority**: P2 (Nice to have)  
**Dependencies**: T015  
**Estimated Time**: 30 minutes

**Description**: Display container status and metadata

**Acceptance Criteria**:
- [ ] List all managed containers with status
- [ ] Show resource usage (container size, volume size)
- [ ] Display last used timestamps
- [ ] Show container health status
- [ ] Format output with status icons and colors

**Implementation Notes**:
- Use status icons: ✅ (running), ⏸️ (stopped), ❌ (not provisioned)
- Include container uptime and Ruby version

---

#### T019 🐳 Enhanced Docker Compose Integration
**Priority**: P1 (Important)  
**Dependencies**: T011  
**Estimated Time**: 45 minutes

**Description**: Update existing Docker Compose generator for persistent containers

**Acceptance Criteria**:
- [ ] Modify existing `docker_compose_generator.rb` for persistent mode
- [ ] Use `sleep infinity` as container command
- [ ] Configure proper working directory and volume mounts
- [ ] Support both persistent and ephemeral modes
- [ ] Maintain backward compatibility with existing volumes

**Implementation Notes**:
- Extend existing generator rather than replacing
- Add mode parameter to generation logic

---

## Phase 3: CLI Enhancement (Days 5-6)

### CLI Command Implementation

#### T020 🖥️ Update Existing exec Command
**Priority**: P0 (Blocking)  
**Dependencies**: T013  
**Estimated Time**: 1.5 hours

**Description**: Enhance current exec command to use persistent containers

**Acceptance Criteria**:
- [ ] Integrate with ContainerManager for persistent execution
- [ ] Maintain backward compatibility with existing options
- [ ] Add progress indicators for provisioning operations
- [ ] Preserve current error handling and help text
- [ ] Support both persistent and ephemeral modes

**Implementation Notes**:
- Modify existing `exec` method in `lib/gem_dock/cli.rb`
- Check mode configuration to determine execution strategy
- Keep current validation and argument parsing

---

#### T021 🖥️ Implement provision Command
**Priority**: P0 (Blocking)  
**Dependencies**: T011, T020  
**Estimated Time**: 1 hour

**Description**: Container lifecycle management command

**Acceptance Criteria**:
- [ ] Subcommands: start, stop, restart, down
- [ ] Support `--ruby-version` option
- [ ] Progress indicators for long operations
- [ ] Confirmation prompts for destructive operations
- [ ] Helpful error messages with suggested actions

**Implementation Notes**:
```bash
gemdock provision start --ruby-version 3.2.0
gemdock provision stop    # stops current version
gemdock provision restart # restart current version
gemdock provision down --ruby-version 3.2.0  # remove container
```

---

#### T022 🖥️ Implement list Command  
**Priority**: P1 (Important)  
**Dependencies**: T018  
**Estimated Time**: 45 minutes

**Description**: Display all managed containers

**Acceptance Criteria**:
- [ ] Show all Ruby versions with status
- [ ] Display last used timestamps
- [ ] Show resource usage information
- [ ] Use status icons and colors
- [ ] Support machine-readable output format

**Implementation Notes**:
- Tabular format with columns: Version, Status, Last Used, Resources
- Option for JSON output: `--format json`

---

#### T023 🖥️ Implement status Command
**Priority**: P1 (Important)  
**Dependencies**: T018  
**Estimated Time**: 30 minutes

**Description**: Show current project status

**Acceptance Criteria**:
- [ ] Display current Ruby version
- [ ] Show container status and health
- [ ] Display configuration summary
- [ ] Show recent activity log
- [ ] Include Docker daemon status

**Implementation Notes**:
- Single-container focus (current version)
- Health check verification
- Config validation check

---

#### T024 🖥️ Implement switch Command
**Priority**: P1 (Important)  
**Dependencies**: T016  
**Estimated Time**: 45 minutes

**Description**: Interactive Ruby version switching

**Acceptance Criteria**:
- [ ] List available Ruby versions
- [ ] Interactive selection menu
- [ ] Handle resource management prompts
- [ ] Update configuration if requested
- [ ] Verify successful switch

**Implementation Notes**:
- Use tty-prompt for version selection
- Show current version prominently
- Auto-provision if version not available

---

#### T025 🖥️ Implement clean Command
**Priority**: P2 (Nice to have)  
**Dependencies**: T017  
**Estimated Time**: 45 minutes

**Description**: Container cleanup operations

**Acceptance Criteria**:
- [ ] Remove stopped containers
- [ ] Support `--all` flag for aggressive cleanup
- [ ] Confirmation prompts with resource details
- [ ] Dry-run mode with `--dry-run`
- [ ] Report cleanup results

**Implementation Notes**:
```bash
gemdock clean           # remove stopped containers
gemdock clean --all     # remove all containers
gemdock clean --dry-run # show what would be removed
```

---

#### T026 🖥️ Implement config Command
**Priority**: P1 (Important)  
**Dependencies**: T003  
**Estimated Time**: 1 hour

**Description**: Configuration management command

**Acceptance Criteria**:
- [ ] Subcommands: get, set, list, reset
- [ ] Validate configuration values
- [ ] Show current configuration
- [ ] Reset to defaults option
- [ ] Configuration file location guidance

**Implementation Notes**:
```bash
gemdock config list                    # show all config
gemdock config get auto_provision      # get specific value
gemdock config set mode ephemeral      # set value
gemdock config reset                   # reset to defaults
```

---

#### T027 🖥️ Add Interactive Prompts Integration
**Priority**: P1 (Important)  
**Dependencies**: T021-T026  
**Estimated Time**: 45 minutes

**Description**: Integrate tty-prompt for consistent user interaction

**Acceptance Criteria**:
- [ ] Consistent prompt styling across commands
- [ ] Graceful degradation on non-TTY terminals
- [ ] Keyboard navigation support
- [ ] Clear option descriptions
- [ ] Respect CI/CD mode (no prompts)

**Implementation Notes**:
- Create shared prompt helper methods
- Check `ENV['CI']` and `$stdin.tty?` for prompt availability
- Use symbols for option values

---

#### T028 🖥️ Enhanced Help and Error Messages
**Priority**: P1 (Important)  
**Dependencies**: T020-T026  
**Estimated Time**: 1 hour

**Description**: Improve CLI user experience with better messages

**Acceptance Criteria**:
- [ ] Command-specific help with examples
- [ ] Error messages with suggested solutions
- [ ] Command discovery hints
- [ ] Configuration guidance in errors
- [ ] Performance tips and warnings

**Implementation Notes**:
- Include examples in Thor command descriptions
- Create error classes with solution suggestions
- Add links to documentation

---

#### T029 🖥️ Add Command Aliases and Shortcuts
**Priority**: P2 (Nice to have)  
**Dependencies**: T020-T026  
**Estimated Time**: 30 minutes

**Description**: Convenient command shortcuts for common operations

**Acceptance Criteria**:
- [ ] Short aliases for common commands
- [ ] Version shortcuts (e.g., `3.2` → `3.2.0`)
- [ ] Smart defaults for missing options
- [ ] Backward compatibility with existing usage

**Implementation Notes**:
```bash
gemdock e bundle install    # alias for exec
gemdock p start             # alias for provision start
gemdock s 3.1              # alias for switch with version shortcut
```

---

## Phase 4: Testing (Days 7-8)

### Unit Tests

#### T030 🧪 Test StateManager
**Priority**: P0 (Blocking)  
**Dependencies**: T004, T005, T006  
**Estimated Time**: 2 hours

**Description**: Comprehensive state management testing

**Acceptance Criteria**:
- [ ] Test state file loading with valid/invalid/missing files
- [ ] Test atomic save operations (including crash simulation)
- [ ] Test state validation and error handling
- [ ] Test state migrations from legacy formats
- [ ] Test concurrent access patterns
- [ ] Achieve >95% code coverage

**Implementation Notes**:
- Use FakeFS for filesystem mocking
- Test corruption recovery scenarios
- Mock Process.pid for temp file testing

---

#### T031 🧪 Test ConfigManager
**Priority**: P0 (Blocking)  
**Dependencies**: T003, T005  
**Estimated Time**: 1.5 hours

**Description**: Configuration management testing

**Acceptance Criteria**:
- [ ] Test configuration loading with defaults
- [ ] Test configuration validation (type checking, enums)
- [ ] Test invalid configuration rejection
- [ ] Test configuration persistence
- [ ] Test merge behavior with partial configs
- [ ] Achieve >95% code coverage

**Implementation Notes**:
- Test each configuration key type validation
- Test edge cases (empty files, invalid YAML)

---

#### T032 🧪 Test ContainerManager
**Priority**: P0 (Blocking)  
**Dependencies**: T010-T014  
**Estimated Time**: 3 hours

**Description**: Container operations testing

**Acceptance Criteria**:
- [ ] Test container lifecycle operations (start/stop/restart)
- [ ] Test health check logic with various failure modes
- [ ] Test command execution with mocked Docker
- [ ] Test auto-provisioning flows
- [ ] Test error recovery scenarios
- [ ] Mock all Docker commands for unit tests
- [ ] Achieve >90% code coverage

**Implementation Notes**:
- Mock Docker commands with predictable responses
- Test both success and failure paths
- Simulate container failures and recovery

---

#### T033 🧪 Test CLI Commands
**Priority**: P0 (Blocking)  
**Dependencies**: T020-T026  
**Estimated Time**: 2 hours

**Description**: CLI command interface testing

**Acceptance Criteria**:
- [ ] Test all command variations with options
- [ ] Test input validation and error handling
- [ ] Test help message generation
- [ ] Mock interactive prompts for automated testing
- [ ] Test command output formatting
- [ ] Achieve >90% code coverage

**Implementation Notes**:
- Mock TTY::Prompt for prompt testing
- Capture STDOUT/STDERR for output verification
- Test both valid and invalid command combinations

---

### Integration Tests

#### T034 🧪 Container Lifecycle Integration Tests
**Priority**: P1 (Important)  
**Dependencies**: T010-T014, Docker daemon  
**Estimated Time**: 2 hours

**Description**: End-to-end container operations with real Docker

**Acceptance Criteria**:
- [ ] Test complete provision → start → exec → stop → clean cycle
- [ ] Test multiple Ruby version isolation
- [ ] Test state persistence across operations
- [ ] Test Docker Compose file generation
- [ ] Test volume persistence and cleanup
- [ ] Require running Docker daemon

**Implementation Notes**:
- Mark tests as `:integration` for optional running
- Clean up Docker resources after each test
- Use unique container names to avoid conflicts

---

#### T035 🧪 Auto-Provisioning Integration Tests
**Priority**: P1 (Important)  
**Dependencies**: T012, T034  
**Estimated Time**: 1.5 hours

**Description**: Test auto-provisioning workflows

**Acceptance Criteria**:
- [ ] Test first-time user flow (auto-provision with prompt)
- [ ] Test stopped container auto-restart
- [ ] Test version switching with resource management
- [ ] Test CI/CD mode (no prompts)
- [ ] Test configuration-driven behavior

**Implementation Notes**:
- Mock user input for prompt testing
- Test with different configuration values
- Verify no prompts in CI environment

---

#### T036 🧪 Error Recovery Integration Tests
**Priority**: P1 (Important)  
**Dependencies**: T014, T034  
**Estimated Time**: 1 hour

**Description**: Test error scenarios with real Docker

**Acceptance Criteria**:
- [ ] Test container crash recovery
- [ ] Test Docker daemon unavailable scenarios
- [ ] Test corrupted state file recovery
- [ ] Test resource cleanup after failures
- [ ] Test recovery messaging and guidance

**Implementation Notes**:
- Simulate container crashes (kill container mid-operation)
- Test recovery from various failure states
- Verify proper cleanup of partial operations

---

### Performance Tests

#### T037 🧪 Command Execution Performance Tests
**Priority**: P1 (Important)  
**Dependencies**: T013, T034  
**Estimated Time**: 1 hour

**Description**: Verify performance targets are met

**Acceptance Criteria**:
- [ ] Command execution overhead <0.6 seconds for running containers
- [ ] State file operations <50ms for read/write
- [ ] Container health checks <2 seconds
- [ ] Container provisioning <5 seconds (excluding image pull)
- [ ] Verify 5-10x improvement over ephemeral mode

**Implementation Notes**:
- Use Benchmark module for timing
- Test with realistic project sizes
- Compare persistent vs ephemeral performance
- Test with multiple Ruby versions

---

## Phase 5: Documentation (Day 9)

### Documentation Tasks

#### T038 📚 Update README.md
**Priority**: P1 (Important)  
**Dependencies**: T020-T026  
**Estimated Time**: 1 hour

**Description**: Update project README with persistent container documentation

**Acceptance Criteria**:
- [ ] Add persistent container mode overview
- [ ] Document all new CLI commands with examples
- [ ] Add configuration reference
- [ ] Include performance comparison
- [ ] Add troubleshooting section
- [ ] Update installation and setup instructions

**Implementation Notes**:
- Include migration guide from ephemeral mode
- Add FAQ section for common issues
- Include performance benchmarks

---

#### T039 📚 Create Migration Guide
**Priority**: P2 (Nice to have)  
**Dependencies**: T038  
**Estimated Time**: 30 minutes

**Description**: Guide for users migrating from ephemeral mode

**Acceptance Criteria**:
- [ ] Document breaking changes
- [ ] Provide migration steps
- [ ] Explain new configuration options
- [ ] Include rollback instructions
- [ ] Address common migration issues

**Implementation Notes**:
- Create separate MIGRATION.md file
- Link from README.md

---

## Task Dependencies

### Dependency Graph

```
Foundation Layer:
T001 → T002, T003, T004, T007
T002 → T005, T008
T003 → T005, T012, T026
T004 → T005, T010, T015
T005 → T006
T007 → T008

Container Layer:
T008 → T009, T010
T009 → T013
T010 → T011, T015, T021
T011 → T012, T019
T012 → T013, T035
T013 → T014, T020, T037
T014 → T036
T015 → T016, T017, T018, T034
T016 → T024
T017 → T025
T018 → T022, T023
T019 → T034

CLI Layer:
T020 → T021, T027, T033
T021 → T024, T027
T022 → T027
T023 → T027
T024 → T027
T025 → T027
T026 → T027
T027 → T028, T029
T028 → T033
T029 → T033

Testing Layer:
T030 → T034
T031 → T034
T032 → T034, T035, T036
T033 → T035, T036
T034 → T035, T036, T037

Documentation:
T038 → T039
```

### Critical Path

**Priority P0 (Blocking)**: T001 → T002 → T008 → T009 → T010 → T011 → T013 → T020 → T021

This critical path represents the minimum viable persistent container functionality.

---

## Implementation Guidelines

### Code Quality Standards

- **Test Coverage**: Minimum 90% for core components, 95% for data management
- **Documentation**: All public methods must have YARD documentation
- **Error Handling**: All errors must include suggested user actions
- **Logging**: All significant operations must be logged
- **Performance**: All operations must meet specified performance targets

### Development Workflow

1. **Implement Foundation** (T001-T007): Core infrastructure
2. **Build Container Layer** (T008-T019): Docker integration
3. **Enhance CLI** (T020-T029): User interface
4. **Add Testing** (T030-T037): Quality assurance
5. **Update Documentation** (T038-T039): User guidance

### Testing Strategy

- **Unit Tests**: Mock all external dependencies (Docker, filesystem)
- **Integration Tests**: Require Docker daemon, use real containers
- **Performance Tests**: Measure against specific targets
- **CI/CD**: All tests must pass, integration tests optional in CI

### Risk Mitigation

- **Docker Dependency**: Graceful fallback to ephemeral mode if Docker unavailable
- **State Corruption**: Atomic saves with backup and recovery
- **Performance Regression**: Performance tests in CI pipeline
- **User Experience**: Extensive help messages and error guidance

---

## Ready for Implementation

All tasks are defined with clear acceptance criteria, dependencies, and implementation notes. The foundation components (StateManager, ConfigManager) should be implemented first, followed by container operations, then CLI enhancements.

**Next Steps**:
1. Begin with T001 (Project Structure)
2. Follow dependency order within each phase
3. Run tests continuously during development
4. Update this document with progress tracking

**Success Criteria**: All 47 tasks completed with 5-10x performance improvement over ephemeral mode, maintaining full backward compatibility.