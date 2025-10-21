# Container Cleanup Implementation

## Overview

Implemented container cleanup operations with idle detection and safe removal of unused containers. This feature helps maintain a clean Docker environment by removing containers that haven't been used recently.

## Implementation Details

### 1. ContainerCleanup Class (`lib/gem_dock/container_cleanup.rb`)

**Purpose**: Manages cleanup of unused containers and volumes based on idle timeout.

**Key Features**:
- Idle detection based on configurable timeout (default: 24 hours)
- Safe removal with confirmation prompts
- Dry-run mode to preview cleanup
- Force mode to skip confirmations
- Comprehensive statistics reporting

**Key Methods**:
- `cleanup(all:, force:, dry_run:)` - Main cleanup operation
- `identify_cleanup_candidates(all:)` - Find containers to clean
- `clean_container(ruby_version, remove_volume:)` - Remove specific container
- `cleanup_stats()` - Get statistics about cleanable containers

**Safety Features**:
- Never removes running containers
- Confirmation prompt before destructive operations
- Dry-run mode to preview changes
- Comprehensive logging of all operations

### 2. CLI Integration (`lib/gem_dock/cli.rb`)

**Command**: `gemdock clean [OPTIONS]`

**Options**:
- `--all, -a` - Remove all stopped containers regardless of age
- `--force, -f` - Skip confirmation prompts
- `--dry-run, -d` - Show what would be cleaned without actually cleaning

**Usage Examples**:

```bash
# Preview cleanup (dry-run)
gemdock clean --dry-run

# Clean idle containers (with confirmation)
gemdock clean

# Clean all stopped containers
gemdock clean --all

# Force cleanup without confirmation
gemdock clean --force

# Clean all without confirmation
gemdock clean --all --force
```

**Output**:
```
Container Statistics:
  Total containers: 3
  Running: 1
  Stopped: 2
  Idle (>24h): 1

The following containers will be removed:
  - Ruby 3.1.0 (last used: 2024-01-15 10:30:00)

This will remove containers and their volumes. Continue? (yes/no): yes

Cleanup complete:
  Cleaned: 1
```

## Test Coverage

### ContainerCleanup Tests (`spec/gem_dock/container_cleanup_spec.rb`): 22 tests

**Test Categories**:
1. **Idle Detection** (4 tests):
   - Identifies containers idle longer than timeout
   - Includes all stopped containers with --all flag
   - Never includes running containers
   - Handles invalid timestamps gracefully

2. **Container Removal** (9 tests):
   - Removes container successfully
   - Removes compose file
   - Updates state
   - Returns success status
   - Handles removal failures
   - Skips missing compose files
   - Respects remove_volume flag

3. **Cleanup Operation** (7 tests):
   - Handles empty candidate list
   - Dry-run mode
   - Confirmation prompts
   - Force mode
   - Mixed success/failure results

4. **Statistics** (1 test):
   - Returns accurate container statistics

5. **Error Handling** (1 test):
   - Logs errors appropriately

### CLI Integration Tests (`spec/gem_dock/cli_integration_spec.rb`): 6 tests

**Test Categories**:
1. **Basic Operation** (2 tests):
   - Displays statistics and no-op message
   - Shows cleanup results

2. **Flags** (3 tests):
   - Dry-run flag behavior
   - All flag behavior
   - Force flag behavior

3. **Error Reporting** (1 test):
   - Reports failed cleanups

## Configuration

The idle timeout can be configured via ConfigManager:

```ruby
# Default: 24 hours
config_manager.set("idle_timeout", 48)  # Set to 48 hours
```

## State Management

The cleanup operation updates the state file to reflect removed containers:
- Sets status to "not_provisioned"
- Clears container_id
- Clears volume_name

## File Cleanup

When removing a container, the following are cleaned:
1. Docker container (via `docker rm`)
2. Docker volume (if remove_volume is true, via `docker volume rm`)
3. Docker Compose file (`~/.gemdock/docker-compose-ruby-X_Y_Z.yml`)
4. State entry (updated, not removed)

## Dependencies

- **DockerCommand**: For Docker operations
- **StateManager**: For state tracking
- **ConfigManager**: For configuration
- **ContainerLifecycle**: For container operations
- **Logger**: For operation logging
- **Utils**: For helper functions (sanitize_version, etc.)

## Integration Points

The cleanup feature integrates with:
1. **State tracking**: Uses last_used timestamps
2. **Container lifecycle**: Checks running status
3. **Docker operations**: Executes removal commands
4. **Configuration**: Reads idle_timeout setting

## Performance Considerations

- Fast operation for small container counts
- Confirmation prompts prevent accidental deletions
- Dry-run mode allows preview without side effects
- Batch operations for multiple containers

## Future Enhancements

Potential improvements (from tasks.md):
1. ✅ Idle timeout detection (implemented)
2. ✅ Confirmation prompts (implemented)
3. ✅ --all and --force flags (implemented)
4. ✅ State updates (implemented)
5. ⬜ Resource usage display (planned)
6. ⬜ Interactive prompts with tty-prompt (planned)

## Test Results

```
ContainerCleanup: 22 examples, 0 failures
CLI Integration (clean): 6 examples, 0 failures
Total: 349 examples, 0 failures
```

## Summary

The container cleanup feature provides:
- Safe, controlled cleanup of unused containers
- Flexible options for different use cases
- Comprehensive testing (28 tests)
- Clear user feedback
- Integration with existing infrastructure

This completes the Container Cleanup Operations requirement from the tasks specification.
