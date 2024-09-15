# GemDock

GemDock is a developer tool for managing development environments in Docker.

## Installation

Install the gem by executing:

    $ gem install gemdock

## Usage

To initialize GemDock in your project:

    $ gemdock init

To provision your development environment:

    $ gemdock provision

To get available commands:

    $ gemdock ls

To run a command:

    $ gemdock run COMMAND

## Guide

* [Use GemDock to develop Rubygems](https://github.com/saiqulhaq/gemdock/blob/main/docs/gem-development-with-gemdoc-example.md)
* [Store and quick start](https://saiqulhaq.id/very-fast-ruby-gem-development-testing)
  
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/saiqulhaq/gemdock.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Gemdock project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/saiqulhaq/gemdock/blob/main/CODE_OF_CONDUCT.md).
