# frozen_string_literal: true

require_relative "lib/puma_release/version"

Gem::Specification.new do |spec|
  spec.name = "puma-release"
  spec.version = PumaRelease::VERSION
  spec.authors = ["Nate Berkopec"]
  spec.email = ["nate.berkopec@gmail.com"]

  spec.summary = "Automate Puma releases"
  spec.description = "Standalone CLI for running Puma's release process against a Puma checkout."
  spec.homepage = "https://github.com/nateberkopec/puma-release"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["LICENSE", "README.md", "exe/*", "lib/**/*.rb", "test/**/*.rb"]
  spec.bindir = "exe"
  spec.executables = ["puma-release"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "ostruct"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "standard"
end
