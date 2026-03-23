# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |test|
  test.libs << "lib" << "test"
  test.pattern = "test/**/*_test.rb"
end

task default: :test
