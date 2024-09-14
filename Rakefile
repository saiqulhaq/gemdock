# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

desc "Run Standard with auto-correct"
task :standard_fix do
  puts "Running Standard with auto-correct..."
  sh "bundle exec standardrb --fix"
end

desc "Run tests and fix code style"
task default: %i[spec standard_fix]
