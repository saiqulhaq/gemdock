# GemDock

GemDock is a developer tool for managing Ruby gem development environments in Docker containers.

## Installation

Install the gem by executing:

    $ gem install gemdock

## Usage

GemDock automatically initializes when you first run a command. It creates docker-compose configuration files in `$HOME/.gemdock`.

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

Each Ruby version gets its own isolated bundle cache, so you can work with multiple versions without conflicts:

```bash
# Work with Ruby 3.3
gemdock exec --ruby-version 3.3.0 bundle install
gemdock exec --ruby-version 3.3.0 rspec spec/

# Switch to Ruby 2.7
gemdock exec --ruby-version 2.7.0 bundle install
gemdock exec --ruby-version 2.7.0 rspec spec/

# Back to Ruby 3.3 (gems are already cached!)
gemdock exec --ruby-version 3.3.0 rake test
```

### Interactive Shell

To open an interactive shell inside the container:

    $ gemdock exec shell
    
    # Or with a specific Ruby version
    $ gemdock exec --ruby-version 3.1.0 shell

### Examples

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
