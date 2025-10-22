# GemDock

GemDock is a developer tool for managing Ruby gem development environments in Docker containers. It provides **persistent containers** for fast, reliable Ruby development across multiple versions.

## Features

- 🚀 **Persistent Containers**: Long-running containers with instant command execution (no startup overhead)
- 🔄 **Multi-Version Support**: Run multiple Ruby versions simultaneously with isolated environments
- ⚡ **Fast Switching**: Switch between Ruby versions in milliseconds
- 💾 **State Management**: Track container status, health, and usage across sessions
- 🎯 **Smart Auto-Provisioning**: Automatic container setup with user prompts or CI/CD mode
- 🔧 **Configuration Management**: Flexible configuration with sensible defaults
- 🛡️ **Error Recovery**: Robust error handling with actionable suggestions

## Installation

Install the gem by executing:

    $ gem install gemdock

## Quick Start

```bash
# Create and start a container for Ruby 3.2.0
gemdock provision create 3.2.0

# Execute commands (container stays running)
gemdock exec bundle install
gemdock exec rspec spec/
gemdock exec ruby script.rb

# Check status
gemdock status

# Switch default version
gemdock switch 3.1.0

# List all containers
gemdock provision list

# Clean up when done
gemdock clean
```

## Usage

### Container Lifecycle Management

#### Create and Provision Containers

```bash
# Create a container for Ruby 3.2.0
gemdock provision create 3.2.0

# Create and start immediately
gemdock provision create 3.1.4
```

#### Start/Stop Containers

```bash
# Start a container
gemdock provision start 3.2.0

# Stop a container (preserves data)
gemdock provision stop 3.2.0

# Restart a container
gemdock provision restart 3.2.0
```

#### List and Remove Containers

```bash
# List all containers with their status
gemdock provision list

# Remove a container (keeps volume)
gemdock provision down 3.2.0

# Remove container and its volume
gemdock provision down 3.2.0 --remove-volume
```

### Execute Commands in Container

To execute arbitrary commands in the container:

    $ gemdock exec gem install bundler 2.4.22
    $ gemdock exec rspec spec/
    $ gemdock exec ruby script.rb

### Ruby Version Selection

You can specify a Ruby version for any command using the `--ruby-version` (or `-r`) flag:

    $ gemdock exec --ruby-version 3.2.0 bundle gem myproject
    $ gemdock exec --ruby-version 2.7.0 rspec spec/
    $ gemdock exec -r 3.1.0 bundle install

Or set a default version with `switch`:

```bash
# Set default Ruby version
gemdock switch 3.2.0

# Now all commands use 3.2.0 by default
gemdock exec bundle install
gemdock exec rspec spec/

# Check current default version
gemdock current
```

Each Ruby version gets its own isolated bundle cache and persistent container:

```bash
# Work with Ruby 3.3 (container stays running)
gemdock exec --ruby-version 3.3.0 bundle install
gemdock exec --ruby-version 3.3.0 rspec spec/

# Switch to Ruby 2.7 (instant switch, no container restart)
gemdock exec --ruby-version 2.7.0 bundle install
gemdock exec --ruby-version 2.7.0 rspec spec/

# Back to Ruby 3.3 (instant, gems are already cached!)
gemdock exec --ruby-version 3.3.0 rake test
```

### Status and Monitoring

```bash
# Show detailed status of current environment
gemdock status

# Output includes:
# - Current default Ruby version
# - Container status (running/stopped)
# - Container health
# - Volume information
# - Last used timestamp
# - Disk usage
```

### Configuration Management

```bash
# List all configuration settings
gemdock config list

# Get a specific setting
gemdock config get auto_provision

# Set a configuration value
gemdock config set auto_provision true
gemdock config set default_ruby_version 3.2.0
gemdock config set mode persistent

# Reset to defaults
gemdock config reset
```

### Cleanup

```bash
# Interactive cleanup (prompts for what to remove)
gemdock clean

# Remove stopped containers automatically
gemdock clean --auto

# Remove containers not used in 30 days
gemdock clean --unused-days 30
```

### Interactive Shell

To open an interactive shell inside the container:

    $ gemdock exec shell
    
    # Or with a specific Ruby version
    $ gemdock exec --ruby-version 3.1.0 shell

### Examples

```bash
# Create a new gem project with Ruby 3.3.0
gemdock provision create 3.3.0
gemdock exec --ruby-version 3.3.0 bundle gem my_awesome_gem

# Run tests across multiple Ruby versions
gemdock provision create 3.2.0
gemdock provision create 3.1.4
gemdock provision create 2.7.8

gemdock exec --ruby-version 3.2.0 rspec spec/
gemdock exec --ruby-version 3.1.4 rspec spec/
gemdock exec --ruby-version 2.7.8 rspec spec/

# Install specific bundler version
gemdock exec gem install bundler 2.4.22

# Run bundle commands
gemdock exec bundle install
gemdock exec bundle update rails

# Open an interactive shell
gemdock exec shell

# Clean up old versions
gemdock provision list
gemdock provision down 2.7.8 --remove-volume
```

## Configuration Reference

GemDock stores configuration in `$HOME/.gemdock/config.yml`. Available settings:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `default_ruby_version` | String | `nil` | Default Ruby version for commands |
| `auto_provision` | Boolean | `false` | Auto-create containers without prompting |
| `mode` | String | `"persistent"` | Container mode (`persistent` or `ephemeral`) |
| `log_level` | String | `"info"` | Logging verbosity (`debug`, `info`, `warn`, `error`) |
| `health_check_enabled` | Boolean | `true` | Enable container health checks |
| `health_check_timeout` | Integer | `30` | Health check timeout in seconds |

### Configuration Examples

```bash
# Enable auto-provisioning (great for CI/CD)
gemdock config set auto_provision true

# Set default Ruby version
gemdock config set default_ruby_version 3.2.0

# Enable debug logging
gemdock config set log_level debug

# Increase health check timeout for slow systems
gemdock config set health_check_timeout 60
```

## How It Works

### Persistent Container Mode

GemDock runs containers in **persistent mode** by default:

- Containers stay running using `sleep infinity`
- Commands execute instantly (no container startup overhead)
- State persists across commands and sessions
- Volumes preserve gems, bundle cache, and project files
- Health checks monitor container status

**Performance Comparison:**

| Operation | Ephemeral Mode | Persistent Mode |
|-----------|----------------|-----------------|
| First command | ~3-5 seconds | ~3-5 seconds |
| Subsequent commands | ~3-5 seconds | ~100-200ms |
| Version switch | ~3-5 seconds | ~100-200ms |

### Version-Specific Resources

GemDock creates isolated environments for each Ruby version:

- **State file**: `$HOME/.gemdock/state.yml` (tracks all containers)
- **Configuration**: `$HOME/.gemdock/config.yml`
- **Docker Compose files**: `$HOME/.gemdock/docker-compose-ruby-<version>.yml`
- **Bundle cache volumes**: `gemdock-ruby-<version>` (e.g., `gemdock-ruby-3-2-0`)
- **Container names**: `gemdock-ruby-<version>` (e.g., `gemdock-ruby-3-2-0`)

This ensures complete isolation:
- No gem conflicts between Ruby versions
- Fast version switching (containers stay running)
- Independent lifecycle management
- Parallel execution across versions

### Auto-Provisioning

GemDock intelligently handles missing containers:

**Interactive Mode** (with TTY):
```bash
$ gemdock exec --ruby-version 3.2.0 bundle install
Container for Ruby 3.2.0 is not provisioned. Would you like to provision it now? (y/N)
```

**CI/CD Mode** (no TTY or `CI=true`):
- With `auto_provision: true`: Automatically provisions
- With `auto_provision: false`: Fails with clear error message

**Stopped Container Auto-Restart**:
- Stopped containers automatically restart when needed
- No prompting required for restart operations

## Troubleshooting

### Container Won't Start

```bash
# Check container status
gemdock status

# View container logs
docker logs gemdock-ruby-3-2-0

# Remove and recreate
gemdock provision down 3.2.0 --remove-volume
gemdock provision create 3.2.0
```

### Permission Denied Errors

Ensure your user can run Docker without sudo:

```bash
# Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Or use Docker Desktop (Mac/Windows)
```

### Corrupted State File

```bash
# Reset state (warning: loses container tracking)
rm ~/.gemdock/state.yml

# Recreate containers
gemdock provision create 3.2.0
```

### Docker Daemon Not Running

```bash
# Check Docker status
docker info

# Start Docker daemon (Linux)
sudo systemctl start docker

# Or start Docker Desktop (Mac/Windows)
```

### Out of Disk Space

```bash
# Clean up unused containers
gemdock clean --auto

# Remove old Docker images
docker system prune -a

# Check volume disk usage
docker system df
```

### Command Execution Fails

```bash
# Check container health
gemdock status

# Restart container
gemdock provision restart 3.2.0

# Check container logs
docker logs gemdock-ruby-3-2-0
```

## Migration from Ephemeral Mode

If upgrading from an older version of GemDock:

1. **Stop all running containers:**
   ```bash
   docker ps --filter "name=gemdock" -q | xargs docker stop
   ```

2. **No data loss:** Bundle caches in volumes are preserved

3. **Update configuration:**
   ```bash
   gemdock config set mode persistent
   ```

4. **Recreate containers:**
   ```bash
   gemdock provision create 3.2.0  # for each version you use
   ```

5. **Verify setup:**
   ```bash
   gemdock provision list
   gemdock status
   ```

## FAQ

### How is this different from rbenv/rvm?

GemDock uses Docker for complete isolation:
- ✅ No system Ruby installation required
- ✅ Consistent across all platforms (Mac, Linux, Windows)
- ✅ Isolated bundle caches per version
- ✅ Clean system (no global gems)
- ✅ Easy cleanup (just remove containers)

### Can I use this in CI/CD?

Yes! Enable auto-provisioning:

```yaml
# .github/workflows/test.yml
- name: Run tests
  run: |
    gem install gemdock
    gemdock config set auto_provision true
    gemdock exec --ruby-version 3.2.0 bundle install
    gemdock exec --ruby-version 3.2.0 rspec spec/
```

### Do containers keep running?

Yes, in persistent mode (default):
- Containers run `sleep infinity` in the background
- Minimal resource usage when idle
- Stop them with `gemdock provision stop` or `gemdock clean`

### How much disk space do containers use?

Each Ruby version uses approximately:
- Base image: ~100-200MB (shared across versions)
- Gems: 50-500MB (depending on dependencies)
- Project files: Variable

Check usage: `docker system df`

### Can I run multiple versions simultaneously?

Yes! Each version has its own container:

```bash
# Terminal 1
gemdock exec --ruby-version 3.2.0 bundle install

# Terminal 2 (simultaneously)
gemdock exec --ruby-version 3.1.4 rspec spec/
```

### How do I update GemDock?

```bash
gem update gemdock
```

Containers and volumes are preserved during updates.

### Can I use this with existing Docker Compose projects?

Yes, GemDock containers are standard Docker containers. They won't interfere with your other projects.

### How do I completely remove GemDock?

```bash
# Remove all containers and volumes
gemdock clean --auto

# Remove configuration
rm -rf ~/.gemdock

# Uninstall gem
gem uninstall gemdock
```

## Examples

```bash
# Install a specific version of bundler
gemdock exec gem install bundler 2.4.22

# Run tests with default Ruby version
gemdock exec rspec spec/

# Run bundle commands with Ruby 3.2.0
gemdock exec --ruby-version 3.2.0 bundle install

# Create a new gem project with Ruby 3.3.0
gemdock exec --ruby-version 3.3.0 bundle gem my_awesome_gem

# Open an interactive shell with Ruby 2.7.0
gemdock exec --ruby-version 2.7.0 shell
```

## How It Works

### Version-Specific Volumes

GemDock creates isolated environments for each Ruby version you use:

- **Configuration files**: `$HOME/.gemdock/docker-compose-ruby-<version>.yml`
- **Bundle cache volumes**: `bundler_data_ruby_<version>`

This ensures that gems compiled for one Ruby version don't conflict with another, and switching between versions is fast after the first initialization.

### Container Lifecycle

Each command runs in a fresh container that is automatically removed after execution. However, your installed gems persist in version-specific Docker volumes, so you don't need to reinstall them every time.

## Command Reference

### Main Commands

| Command | Description |
|---------|-------------|
| `gemdock exec COMMAND` | Execute command in container |
| `gemdock provision SUBCOMMAND` | Manage container lifecycle |
| `gemdock config SUBCOMMAND` | Manage configuration |
| `gemdock switch VERSION` | Set default Ruby version |
| `gemdock current` | Show current default version |
| `gemdock status` | Show environment status |
| `gemdock clean` | Remove unused containers |

### Provision Subcommands

| Command | Description |
|---------|-------------|
| `gemdock provision create VERSION` | Create new container |
| `gemdock provision start [VERSION]` | Start container |
| `gemdock provision stop [VERSION]` | Stop container |
| `gemdock provision restart [VERSION]` | Restart container |
| `gemdock provision down VERSION` | Remove container |
| `gemdock provision list` | List all containers |

### Config Subcommands

| Command | Description |
|---------|-------------|
| `gemdock config list` | Show all settings |
| `gemdock config get KEY` | Get setting value |
| `gemdock config set KEY VALUE` | Set setting value |
| `gemdock config reset` | Reset to defaults |

## Guide

* [Use GemDock to develop Rubygems](https://github.com/saiqulhaq/gemdock/blob/main/docs/gem-development-with-gemdoc-example.md)
* [Story and Quick Start](https://saiqulhaq.id/very-fast-ruby-gem-development-testing)
  
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/saiqulhaq/gemdock.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Gemdock project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/saiqulhaq/gemdock/blob/main/CODE_OF_CONDUCT.md).
