# frozen_string_literal: true

require_relative "lib/gemdock/version"

Gem::Specification.new do |spec|
  spec.name = "gemdock"
  spec.version = Gemdock::VERSION
  spec.authors = ["Saiqul Haq"]
  spec.email = ["saiqulhaq@gmail.com"]

  spec.summary = "A developer tool for managing RubyGem development environments in Docker"
  spec.description = "GemDock creates and manages Docker-based development environments using the dip gem"
  spec.homepage = "https://github.com/saiqulhaq/gemdock"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/saiqulhaq/gemdock"
  spec.metadata["changelog_uri"] = "https://github.com/saiqulhaq/gemdock/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"
  spec.add_dependency "dip"
end
