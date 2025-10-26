# Implementation Plan: Persistent Container Mode with Auto-Provisioning

**Branch**: `001-persistent-containers` | **Date**: 2025-10-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-persistent-containers/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

**Primary Requirement**: Enhance Gemdock to use persistent Docker containers with auto-provisioning, supporting multiple Ruby versions with intelligent switching, achieving 5-10x performance improvement (0.3-0.6s overhead vs 1.5-3s in ephemeral mode).

**Technical Approach**: 
- Replace `docker run --rm` with long-running containers using `sleep infinity` and `docker exec` for command execution
- Implement state tracking in `$PROJECT_ROOT/.gemdock/state.yml` to manage container lifecycle (running/stopped/not_provisioned)
- Add container lifecycle management commands (provision, list, status, switch, clean) using Thor CLI framework
- Auto-provision containers with user confirmation when not available
- Support both persistent (default) and ephemeral (opt-in) modes via `$PROJECT_ROOT/.gemdock/config.yml`
- Maintain version-specific isolation with per-version Docker Compose files and volumes

## Technical Context

**Language/Version**: Ruby 2.6.0+ (gemdock runtime), managing containers for Ruby 2.7.0-3.3.x (target versions)
**Primary Dependencies**: 
- Thor 1.3.0+ (CLI framework, already in use)
- tty-prompt 0.23.1+ (interactive prompts for version switching, cleanup confirmations)
- Docker Engine 20.10+ (container runtime)
- Docker Compose V2 (or docker-compose V1.29+) for multi-container configuration
**Storage**: 
- YAML files for configuration (`$PROJECT_ROOT/.gemdock/config.yml`) and state (`$PROJECT_ROOT/.gemdock/state.yml`)
- Per-version Docker Compose files: `$PROJECT_ROOT/.gemdock/docker-compose-ruby-X-Y-Z.yml`
- Named Docker volumes: `bundler_data_ruby_X_Y_Z` for gem isolation
**Testing**: 
- RSpec 3.12+ (existing test framework)
- FakeFS for filesystem mocking in tests
- Integration tests requiring actual Docker daemon (can use ephemeral mode in CI)
**Target Platform**: 
- macOS and Linux development environments (Docker for Mac/Linux)
- Local Docker daemon only (no remote Docker support)
**Project Type**: Single Ruby gem project (CLI tool)
**Performance Goals**: 
- Command execution overhead: <0.6 seconds for running containers (vs 1.5-3s ephemeral)
- Container provisioning: <5 seconds (excluding Docker image pull)
- 5-10x performance improvement for repeated command execution
- State file operations: <50ms for read/write
**Constraints**: 
- Container health checks must complete in <2 seconds
- Progress indicators required for operations >1 second
- State file updates must be atomic (temp file + rename)
- Auto-provisioning requires user confirmation by default
- Must maintain backward compatibility with existing volumes
**Scale/Scope**: 
- Support 1-5 concurrent Ruby version containers per user
- State file tracks up to 20 Ruby versions (typical gem testing matrix)
- Log file rotation at 10MB (prevent unbounded growth)
- Config file supports 10-15 configuration parameters

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Performance First (Principle I) - ✅ PASS
- **Requirement**: Persistent containers with docker exec, <0.6s overhead
- **Status**: COMPLIANT - Core feature implements this principle
- **Evidence**: FR-001, FR-024 specify docker exec and <0.6s overhead target

### User Experience Excellence (Principle II) - ✅ PASS
- **Requirement**: Auto-provisioning, minimal prompts, progress indicators
- **Status**: COMPLIANT - Auto-provisioning with confirmation, progress for >1s operations
- **Evidence**: FR-002, FR-013, User Story 2 acceptance scenarios

### Resource Management Intelligence (Principle III) - ✅ PASS
- **Requirement**: Container state tracking, idle detection, cleanup tools
- **Status**: COMPLIANT - State file, list/status/clean commands, volume isolation
- **FR-003, FR-008, FR-009, FR-011, FR-015

### Developer Transparency (Principle IV) - ✅ PASS
- **Requirement**: Show provisioning, progress indicators, version prefixes, logging
- **Status**: COMPLIANT - All operations logged, version prefixes, status visibility
- **Evidence**: FR-012, FR-013, FR-019, User Story 6

### Error Resilience and Recovery (Principle V) - ✅ PASS
- **Requirement**: Health checks, auto-recovery, graceful fallbacks
- **Status**: COMPLIANT - Health checks before exec, auto-recovery from failures
- **Evidence**: FR-004, FR-005, Edge case: container health failure

### Configuration Flexibility (Principle VI) - ✅ PASS
- **Requirement**: Support persistent and ephemeral modes, config file
- **Status**: COMPLIANT - Config file with mode setting, ephemeral mode opt-in
- **Evidence**: FR-006, FR-021, FR-022, FR-023

### Tech Stack Simplicity (Principle VII) - ✅ PASS
- **Requirement**: Minimal dependencies, avoid over-engineering
- **Status**: COMPLIANT - Only Thor, tty-prompt, Docker, YAML files
- **Evidence**: Technical Context dependencies, no database/web frameworks

### State Management Clarity (Principle VIII) - ✅ PASS
- **Requirement**: Human-readable state in $PROJECT_ROOT/.gemdock/state.yml, atomic updates
- **Status**: COMPLIANT - YAML state file, atomic writes via temp+rename
- **Evidence**: FR-003, Technical Context constraints, Edge case: corrupted state

### Testing Standards (Principle IX) - ✅ PASS
- **Requirement**: Comprehensive test coverage including edge cases and integration tests
- **Status**: COMPLIANT - Test strategy defined with unit, integration, and performance tests
- **Evidence**: 
  * quickstart.md documents comprehensive testing strategy
  * Unit tests for each manager component
  * Integration tests with real Docker operations
  * Performance tests for <0.6s overhead requirement
  * Edge case coverage in test plans

### Documentation Excellence (Principle X) - ✅ PASS
- **Requirement**: Help messages, examples, error messages with solutions
- **Status**: COMPLIANT - Complete documentation generated in Phase 1
- **Evidence**: 
  * cli-commands.md documents all commands with examples and error messages
  * quickstart.md provides implementation guide with examples
  * data-model.md documents all entities and validation rules
  * Each error condition includes suggested action

**GATE STATUS**: ✅ PASS - All principles verified post-design

**Re-evaluation Notes**:
- Phase 1 design artifacts (data-model.md, contracts/cli-commands.md, quickstart.md) confirm comprehensive coverage
- Test strategy addresses all constitution requirements (unit, integration, edge cases)
- Documentation provides clear examples and error recovery guidance
- No violations or concerns identified

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
lib/
├── gemdock.rb                    # Main entry point
├── gem_dock.rb                   # Alias for compatibility
└── gem_dock/
    ├── cli.rb                    # Thor-based CLI interface (EXISTING - will be enhanced)
    ├── version.rb                # Version constant (EXISTING)
    ├── state_manager.rb          # NEW: Container state tracking in $PROJECT_ROOT/.gemdock/state.yml
    ├── config_manager.rb         # NEW: Configuration management in $PROJECT_ROOT/.gemdock/config.yml
    ├── container_manager.rb      # NEW: Docker container lifecycle operations
    ├── docker_compose_generator.rb  # EXISTING: Generate per-version compose files
    └── logger.rb                 # NEW: Operation logging to $PROJECT_ROOT/.gemdock/logs/gemdock.log

spec/
├── spec_helper.rb                # RSpec configuration (EXISTING)
├── gemdock_spec.rb              # Main spec (EXISTING)
└── gem_dock/
    ├── cli_spec.rb              # CLI tests (EXISTING - will be enhanced)
    ├── state_manager_spec.rb    # NEW: State management tests
    ├── config_manager_spec.rb   # NEW: Configuration tests
    ├── container_manager_spec.rb # NEW: Container lifecycle tests
    └── integration/
        └── persistent_mode_spec.rb  # NEW: End-to-end integration tests

$PROJECT_ROOT/.gemdock/           # Project-specific data directory (created on first use)
├── config.yml                    # Project configuration
├── state.yml                     # Container state tracking
├── docker-compose-ruby-*.yml     # Per-version compose files
└── logs/
    └── gemdock.log              # Operation logs
```

**Structure Decision**: Single project structure (Option 1) is appropriate for this Ruby gem CLI tool. The existing structure already separates concerns with lib/ for source and spec/ for tests. We're adding new modules (StateManager, ConfigManager, ContainerManager) alongside the existing CLI class, following the established pattern of one class per file in gem_dock/ subdirectory.

**Important**: Changed from `$PROJECT_ROOT/.gemdock/` (user home directory) to `$PROJECT_ROOT/.gemdock/` (project-specific directory) to enable per-project isolation. This allows different projects to have independent container state, configurations, and logs.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Phase 0: Research & Design - ✅ COMPLETED

**Artifacts Generated**:
- ✅ `research.md` - All technical unknowns resolved with decisions, rationale, and alternatives
- ✅ `data-model.md` - Complete entity definitions with validation rules and state transitions
- ✅ `contracts/cli-commands.md` - Full CLI command specifications with examples and error handling
- ✅ `quickstart.md` - Developer implementation guide with architecture, patterns, and testing strategy
- ✅ `.github/copilot-instructions.md` - Updated agent context with new technologies

**Key Decisions from Research**:
1. **Container Command**: Use `sleep infinity` for long-running containers (standard Docker pattern)
2. **Health Checks**: Use `docker exec <container> ruby --version` for fast, reliable verification
3. **State Atomicity**: Temp file + atomic rename for corruption-safe updates
4. **Interactive Detection**: Allowlist of known commands (shell, irb, pry, etc.)
5. **Auto-Provisioning UX**: Three-tier approach (auto-provision enabled/disabled/CI mode)
6. **State Machine**: Three states (not_provisioned, stopped, running) with 5 valid transitions
7. **Version Switching**: Interactive prompt with 3 options (stop old, keep both, cancel)
8. **Error Recovery**: Layered recovery (health check → restart → reprovision → clear error)

**Constitution Re-evaluation**: ✅ ALL PRINCIPLES PASS

---

## Planning Phase Complete

**Status**: ✅ Planning phase completed successfully

**Generated Artifacts**:
1. `plan.md` (this file) - Implementation plan with technical context and constitution compliance
2. `research.md` - Technical decisions with rationale and alternatives
3. `data-model.md` - Complete entity definitions and validation rules
4. `contracts/cli-commands.md` - CLI command specifications
5. `quickstart.md` - Developer implementation guide
6. `.github/copilot-instructions.md` - Updated agent context

**Next Command**: `/speckit.tasks` to break down implementation into actionable tasks

**Branch**: `001-persistent-containers`  
**Feature Directory**: `/specs/001-persistent-containers/`