# frozen_string_literal: true

require "rake/testtask"
require "standard/rake"

Rake::TestTask.new do |test|
  test.libs << "lib" << "test"
  test.pattern = "test/**/*_test.rb"
end

task default: [:test, :standard]
