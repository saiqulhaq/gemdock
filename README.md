# GemDock

GemDock is a developer tool for managing Ruby gem development environments in Docker containers.

## Installation

Install the gem by executing:

    $ gem install gemdock

## Usage

GemDock automatically initializes when you first run a command. It creates a `docker-compose.yml` file in `$HOME/.gemdock`.

### Execute Commands in Container

To execute arbitrary commands in the container:

    $ gemdock exec gem install bundler 2.4.22
    $ gemdock exec rspec spec/
    $ gemdock exec ruby script.rb

### Interactive Shell

To open an interactive shell inside the container:

    $ gemdock exec shell

### Examples

```bash
# Install a specific version of bundler
gemdock exec gem install bundler 2.4.22

# Run tests
gemdock exec rspec spec/

# Run bundle commands
gemdock exec bundle install

# Open an interactive shell
gemdock exec shell
```

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
