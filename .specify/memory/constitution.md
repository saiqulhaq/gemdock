<!--
SYNC IMPACT REPORT:
Version Change: INITIAL → 1.0.0
Rationale: Initial constitution establishing foundational principles for GemDock project.

Modified Principles: N/A (initial creation)
Added Sections: All 10 core principles, Technical Architecture, Development Standards, Governance
Removed Sections: None

Templates Status:
- ⚠ .specify/templates/plan-template.md - Review and align with constitution principles
- ⚠ .specify/templates/spec-template.md - Review and align with constitution principles  
- ⚠ .specify/templates/tasks-template.md - Review and align with constitution principles
- ⚠ .specify/templates/commands/*.md - Review for principle alignment

Follow-up TODOs:
- Review all template files to ensure alignment with constitution principles
- Update agent guidance files if they exist
- Ensure test coverage requirements match Principle IX standards
-->

# GemDock Constitution

## Core Principles

### I. Performance First (NON-NEGOTIABLE)
GemDock MUST prioritize persistent containers with `docker exec` over ephemeral `docker run --rm` for all non-CI/CD workflows.

**Rules:**
- Default execution mode MUST use long-running containers with `docker exec`
- Container provisioning MUST happen once per Ruby version, not per command
- Execution overhead MUST be reduced to 0.3-0.6 seconds (5-10x improvement over ephemeral mode)
- Ephemeral mode MAY be supported as an opt-in configuration for CI/CD environments
- Container lifecycle management MUST minimize startup/teardown operations

**Rationale:** Developer productivity depends on fast command execution. Persistent containers eliminate 1.5-3 second overhead per command, enabling rapid iteration cycles and improving developer experience dramatically.

### II. User Experience Excellence
GemDock MUST provide seamless, auto-provisioning workflows that feel native-like, minimizing user prompts while maintaining transparency.

**Rules:**
- Auto-provisioning MUST be the default behavior when containers don't exist
- User prompts MUST be limited to critical decisions (e.g., version conflicts, resource cleanup)
- All operations MUST provide clear progress indicators for actions taking >1 second
- Error messages MUST guide users toward solutions, not just report problems
- Interactive commands (shell, irb, pry) MUST be automatically detected and handled correctly
- Command output MUST be prefixed with Ruby version indicator for clarity

**Rationale:** The best developer tools are invisible. GemDock should handle infrastructure concerns automatically while keeping developers informed about what's happening.

### III. Resource Management Intelligence
GemDock MUST implement intelligent container lifecycle management with clear visibility, automatic cleanup options, and protection against resource bloat.

**Rules:**
- Each Ruby version MUST have isolated volumes (format: `bundler_data_ruby_X_Y_Z`)
- Container state MUST be tracked in `$PROJECT_ROOT/.gemdock/state.yml` with timestamps
- Idle containers (>24 hours default) MUST be detectable and cleanable
- `gemdock list` MUST show all containers with status indicators (✓ running, ⏸ stopped, ✗ not provisioned)
- `gemdock clean` MUST provide safe cleanup with confirmation prompts
- Version switching MUST prompt users about resource implications when multiple containers running

**Rationale:** Multiple Ruby version containers can consume significant resources. Clear visibility and management tools prevent resource bloat while maintaining flexibility.

### IV. Developer Transparency (NON-NEGOTIABLE)
GemDock MUST always show what's happening during provisioning, execution, and version switching operations.

**Rules:**
- Container provisioning MUST display: "Creating Ruby X.Y.Z container..."
- Long operations (>2 seconds) MUST show progress indicators
- All commands MUST prefix output with `[Ruby X.Y.Z]` indicator
- `gemdock status` MUST show current Ruby version, container state, and resource usage
- Docker operations MUST be logged to `$PROJECT_ROOT/.gemdock/logs/gemdock.log`
- Health checks and auto-recovery attempts MUST notify users

**Rationale:** Developers need to understand what GemDock is doing, especially when managing Docker infrastructure. Transparency builds trust and enables troubleshooting.

### V. Error Resilience and Recovery
GemDock MUST implement graceful fallbacks for container failures, with health checks and automatic recovery that doesn't interrupt developer flow.

**Rules:**
- Health checks MUST verify container responsiveness before `docker exec` commands
- Unresponsive containers MUST trigger automatic reprovisioning with notification
- Corrupted state files MUST be recoverable with defaults
- Docker daemon unavailability MUST be detected with helpful error messages
- Missing images MUST trigger automatic pull with progress indicators
- Container name conflicts MUST be resolved automatically or with clear guidance

**Rationale:** Containers can fail, Docker can crash, state can corrupt. Graceful recovery keeps developers productive instead of forcing manual intervention.

### VI. Configuration Flexibility
GemDock MUST support both persistent mode (default, for development) and ephemeral mode (for CI/CD) to accommodate different use cases.

**Rules:**
- Configuration MUST be stored in `$PROJECT_ROOT/.gemdock/config.yml`
- Persistent mode MUST be the default for local development
- Ephemeral mode MUST use `docker run --rm` behavior (current implementation)
- Mode switching MUST be supported via `gemdock config set mode <persistent|ephemeral>`
- Auto-provisioning behavior MUST be configurable per user preference
- Configuration options MUST include: mode, auto_provision, auto_cleanup_idle, idle_timeout_hours

**Rationale:** Different contexts have different needs. Local development benefits from persistent containers; CI/CD needs ephemeral isolation.

### VII. Tech Stack Simplicity
GemDock MUST use minimal dependencies and avoid over-engineering.

**Rules:**
- CLI framework: Thor (already in use)
- Interactive prompts: tty-prompt only
- Container orchestration: Docker and Docker Compose only (no Kubernetes, no exotic tools)
- State management: YAML files (human-readable, version-controllable)
- Logging: Ruby stdlib Logger
- No database dependencies
- No web frameworks or HTTP servers
- Dependencies MUST be justified in architecture decisions

**Rationale:** Simple tech stacks are easier to maintain, debug, and contribute to. GemDock should be a focused tool, not a platform.

### VIII. State Management Clarity
GemDock MUST maintain clear, human-readable state files that track container status, Ruby versions, and user preferences.

**Rules:**
- State file location: `$PROJECT_ROOT/.gemdock/state.yml`
- State MUST include: current_ruby, preferences, containers hash
- Container entries MUST include: last_used timestamp, container_id, status
- State file MUST be valid YAML at all times
- Corrupted state MUST trigger recreation with defaults, not crashes
- State updates MUST be atomic (write to temp file, then rename)
- State file format MUST be documented in README

**Rationale:** Human-readable state files enable debugging, manual intervention if needed, and understanding of GemDock's behavior.

### IX. Testing Standards (NON-NEGOTIABLE)
GemDock MUST ensure comprehensive test coverage for container lifecycle, version switching, error scenarios, and edge cases.

**Rules:**
- Test coverage MUST include:
  * Container provisioning and health checks
  * Version switching with running/stopped containers
  * Error recovery scenarios (crashed containers, corrupted state)
  * Multi-version concurrent operation
  * Configuration changes and mode switching
  * Interactive vs non-interactive command detection
  * Volume isolation between Ruby versions
- Edge cases MUST be tested: Docker daemon down, network issues, disk space, name conflicts
- Integration tests MUST verify actual Docker operations (not just mocked)
- Test suite MUST run in CI/CD environment (using ephemeral mode)
- New features MUST include tests before merge

**Rationale:** GemDock manages critical developer infrastructure. Bugs in container management or state handling can break developer workflows. Comprehensive testing is non-negotiable.

### X. Documentation Excellence
GemDock MUST provide clear help messages, examples, and error messages that guide users toward solutions.

**Rules:**
- Every command MUST have: description, usage examples, option explanations
- `gemdock help` MUST show common workflows, not just command lists
- Error messages MUST include:
  * What went wrong
  * Why it happened (if detectable)
  * Suggested fix or command to resolve
- README MUST include:
  * Quick start guide
  * Common workflows
  * Troubleshooting section
  * Configuration reference
- DESIGN.md MUST document architecture decisions and rationale
- Code comments MUST explain "why", not "what"
- Breaking changes MUST be documented in CHANGELOG.md

**Rationale:** Good documentation is the difference between a useful tool and an abandoned tool. Users should never feel lost or blocked.

## Technical Architecture Standards

### Container Naming Convention
- Format: `gemdock-ruby-X-Y-Z` (e.g., `gemdock-ruby-3-2-0`)
- Volume format: `bundler_data_ruby_X_Y_Z`
- Docker Compose files: `$PROJECT_ROOT/.gemdock/docker-compose-ruby-X-Y-Z.yml`

### File Structure Requirements
```
$PROJECT_ROOT/.gemdock/
  ├── config.yml         # User configuration
  ├── state.yml          # Container state tracking
  ├── docker-compose-ruby-*.yml  # Per-version compose files
  └── logs/
      └── gemdock.log    # Operation logs
```

### Command Execution Flow
1. Parse command and options
2. Determine Ruby version (explicit flag or default)
3. Check container state
4. Auto-provision if needed (with user confirmation if configured)
5. Verify container health
6. Execute via `docker exec` (persistent) or `docker run` (ephemeral)
7. Update state timestamps
8. Log operation

## Development Standards

### Code Organization
- CLI commands: `lib/gem_dock/cli.rb`
- State management: `lib/gem_dock/state_manager.rb`
- Config management: `lib/gem_dock/config_manager.rb`
- Container operations: `lib/gem_dock/container_manager.rb`
- Logging: `lib/gem_dock/logger.rb`

### Error Handling
- Always catch Docker-related exceptions
- Provide recovery suggestions in error messages
- Log errors to file for debugging
- Never expose stack traces to end users (unless --verbose)
- Gracefully degrade when Docker unavailable

### Performance Targets
- Container health check: <200ms
- Docker exec command: <500ms overhead
- Container provisioning: <5 seconds (excluding image pull)
- State file operations: <50ms

## Governance

This constitution supersedes all other development practices and guidelines for the GemDock project.

**Amendment Process:**
1. Proposed changes MUST be documented in pull request description
2. Proposed changes MUST include version bump rationale (MAJOR/MINOR/PATCH)
3. Breaking principle changes (MAJOR) require maintainer approval and migration plan
4. New principles (MINOR) require justification and impact analysis
5. Clarifications (PATCH) can be approved by any maintainer

**Compliance:**
- All pull requests MUST verify compliance with constitution principles
- Code reviews MUST check for principle violations
- New features MUST align with core principles or justify exceptions
- CI/CD MUST enforce testing standards from Principle IX

**Versioning Policy:**
- MAJOR: Backward incompatible principle removals or redefinitions
- MINOR: New principles added or materially expanded guidance
- PATCH: Clarifications, wording improvements, non-semantic refinements

**Review Cycle:**
- Constitution MUST be reviewed quarterly for relevance
- Outdated principles MUST be updated or removed
- New challenges MUST trigger principle evaluation

**Version**: 1.0.0 | **Ratified**: 2025-10-19 | **Last Amended**: 2025-10-19
