# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in gemdock.gemspec
gemspec

less_than_2_7 = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.7")
fakefs_version = less_than_2_7 ? "~> 1.8" : "~> 2.5"

gem "fakefs", fakefs_version
gem "pry", "~> 0.14.2"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "simplecov", "~> 0.22.0"

standard_version = less_than_2_7 ? "~> 1.28.0" : ">= 1.35.1"
gem "standard", standard_version
