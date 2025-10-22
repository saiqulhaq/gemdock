# Integration Tests

This directory contains integration tests that interact with real Docker containers. These tests verify end-to-end functionality of GemDock's persistent container features.

## Running Integration Tests

Integration tests are excluded by default because they require Docker to be running. To run them:

```bash
RUN_INTEGRATION_TESTS=1 bundle exec rspec spec/integration
```

Or run a specific integration test file:

```bash
RUN_INTEGRATION_TESTS=1 bundle exec rspec spec/integration/container_lifecycle_integration_spec.rb
RUN_INTEGRATION_TESTS=1 bundle exec rspec spec/integration/auto_provisioning_integration_spec.rb
```

## Requirements

- Docker daemon must be running
- Docker must be accessible without sudo (user in docker group)
- Sufficient disk space for test containers and volumes
- Network access for pulling Ruby Docker images

## What's Covered

### Container Lifecycle Integration Tests (`container_lifecycle_integration_spec.rb`)

Tests the full container lifecycle operations:

1. **Complete provision → start → exec → stop → clean cycle**
   - Provisions a container for Ruby 3.2.0
   - Starts the container and waits for running state
   - Executes commands inside the container
   - Stops the container
   - Cleans up container and volume

2. **Multiple Ruby version isolation**
   - Provisions two different Ruby versions (3.2.0 and 3.1.4)
   - Starts both simultaneously
   - Verifies each has the correct Ruby version
   - Tests independent container names and states

3. **State persistence across operations**
   - Tests start/stop/restart cycles
   - Verifies state consistency
   - Tracks last_used timestamps
   - Ensures container name remains stable

4. **Docker Compose file generation**
   - Validates compose file creation
   - Parses YAML structure
   - Verifies service configuration (image, command, volumes)

5. **Volume persistence and cleanup**
   - Creates data in volume
   - Stops and starts container
   - Verifies data persists
   - Tests volume removal

6. **Error handling during lifecycle operations**
   - Non-existent container handling
   - Start when already running (no error)
   - Stop when already stopped (no error)

### Auto-Provisioning Integration Tests (`auto_provisioning_integration_spec.rb`)

Tests the automatic provisioning workflows:

1. **First-time user flow with auto-provision**
   - Prompts user and provisions on confirmation
   - Skips provisioning when user declines
   - Auto-provisions without prompting when enabled

2. **Stopped container auto-restart**
   - Automatically restarts stopped containers
   - No prompting for restart operations

3. **Version switching with resource management**
   - Provisions and switches between Ruby versions
   - Tests multi-version container coexistence
   - Verifies state tracking across versions

4. **CI/CD mode (no prompts)**
   - Respects CI environment variable
   - Skips prompts in non-interactive environments
   - Auto-provisions when enabled in CI mode

5. **Configuration-driven behavior**
   - Tests mode configuration (persistent vs ephemeral)
   - Verifies container command configuration

6. **Idempotency**
   - Safe to call ensure_ready multiple times
   - Reuses existing containers
   - No duplicate provisioning

## Test Isolation

All integration tests use unique container names and temporary directories to avoid conflicts:

- Container names: `gemdock-test-ruby-X-X-X-TIMESTAMP`
- Volumes: `gemdock-test-ruby-X-X-X-TIMESTAMP`
- Test directories: Temporary `.gemdock` directories in system tmpdir

Tests automatically clean up all resources (containers, volumes, files) after each test run.

## Cleanup

If tests are interrupted or fail to clean up, you can manually remove test resources:

```bash
# Remove all test containers
docker ps -a --filter "name=gemdock-test" -q | xargs docker rm -f

# Remove all test volumes
docker volume ls --filter "name=gemdock-test" -q | xargs docker volume rm

# Remove test directories (they're in system tmpdir and will be cleaned up on reboot)
```

## Development

When adding new integration tests:

1. Tag tests with `:integration`
2. Use `IntegrationHelper` methods for Docker operations
3. Use `unique_container_name` and `unique_compose_file` for test isolation
4. Leverage automatic cleanup hooks (included via `:integration` tag)
5. Mock `PromptHelper` for interactive prompts to avoid hanging tests
6. Mock `tty_available?` when testing interactive vs CI behavior
7. Add test scenarios to this README
