# Develop Hola Gem with Gemdock and Ruby v2.7-v3.3

Let's follow the tutorial from RubyGems.org to create a simple gem called Hola using Gemdock. This tutorial is based on ["Make Your Own Gem"](https://guides.rubygems.org/make-your-own-gem/) by the RubyGems team.

We'll start with Ruby 2.7 and then demonstrate version switching.

## Setting Up Gemdock

Ensure you have Ruby installed (minimum version 2.6). Install Gemdock by running:

```bash
gem install gemdock
```

## Creating the Hola Gem

### 1. Initialize the Hola Gem project:

```bash
bundler gem hola
cd hola
```

FYI: You can get the source code of this tutorial at [https://github.com/saiqulhaq/hola](https://github.com/saiqulhaq/hola)

### 2. Update the Hola Gemspec

Replace the content of `hola.gemspec` with:

```ruby
# frozen_string_literal: true

require_relative "lib/hola/version"

Gem::Specification.new do |spec|
  spec.name = "hola"
  spec.version = Hola::VERSION
  spec.authors = ["Your Name"]
  spec.email = ["your.email@example.com"]
  spec.summary = "A simple hello world gem"
  spec.description = "A simple gem"
  spec.homepage = "https://github.com/yourusername/hola"
  spec.license = "MIT"
  spec.files = Dir["lib/**/*"]
  spec.require_paths = ["lib"]
end
```

### 3. Implement the Hola Gem

Edit `lib/hola.rb`:

```ruby
require_relative "hola/version"
require_relative "hola/translator"

module Hola
  class Error < StandardError; end

  def self.hi(language = "english")
    translator = Translator.new(language)
    translator.hi
  end

  def self.greet(name:, language: "english")
    translator = Translator.new(language)
    greeting = translator.hi

    if RUBY_VERSION >= "3.0.0" && defined?(Ractor)
      Ractor.new(greeting, name) do |greeting, name|
        "#{greeting}, #{name}!"
      end.take
    else
      Thread.new(greeting, name) do |greeting, name|
        "#{greeting}, #{name}!"
      end.value
    end
  end
end
```

Create `lib/hola/translator.rb`:

```ruby
class Hola::Translator
  def initialize(language)
    @language = language
  end

  def hi
    case @language
    when "spanish"
      "hola mundo"
    else
      "hello world"
    end
  end
end
```

### 4. Add tests in `spec/hola_spec.rb`:

```ruby
RSpec.describe Hola do
  it "has a version number" do
    expect(Hola::VERSION).not_to be nil
  end

  it "says hello in English" do
    expect(Hola.hi("english")).to eq("hello world")
  end

  it "says hello in Spanish" do
    expect(Hola.hi("spanish")).to eq("hola mundo")
  end

  it "greets a person using Ractor" do
    expect(Hola.greet(name: "Alice")).to eq("hello world, Alice!")
  end
end
```

## 5. Testing

Gemdock will automatically initialize when you first run a command. Run the RSpec tests:

```bash
gemdock exec rspec
```

You can also test in IRB. Open an interactive shell:

```bash
gemdock exec shell
```

Inside the container, run `irb`.  

Inside IRB:

```ruby
require_relative 'lib/hola'
Hola.hi 'spanish'
Hola.greet(name: 'World', language: 'spanish')
```

## 6. Working with Different Commands

Run bundle install:

```bash
gemdock exec bundle install
```

Run other gem commands:

```bash
gemdock exec gem install bundler 2.4.22
gemdock exec rake -T
```

Note: The `.greet` method demonstrates the difference between Ruby 2.7 and 3.x. It's not intended for production use.

This revised version provides a clear, step-by-step guide to creating a gem with Gemdock using the new exec-based interface.  

FYI: You can get the source code of this tutorial at [https://github.com/saiqulhaq/hola](https://github.com/saiqulhaq/hola)
