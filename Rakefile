# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Rake::TestTask.new do |test|
  test.libs << "lib" << "test"
  test.pattern = "test/**/*_test.rb"
end

desc "Run flog"
task :flog do
  output = `bundle exec flog -a lib`
  threshold = (ENV["FLOG_THRESHOLD"] || 104).to_i
  method_scores = []

  output.each_line do |line|
    next unless line =~ /^\s*(\d+\.\d+):\s+(.+#.+)\s+(.+\.rb)/

    method_scores << [$1.to_f, "#{$2.strip} #{$3.strip}"]
  end

  failing_methods = method_scores.select { |score, _method_name| score > threshold }
  if failing_methods.any?
    puts "\nFlog failed: Methods with complexity score > #{threshold}:"
    failing_methods.each { |score, method_name| puts "  #{score}: #{method_name}" }
    exit 1
  end
end

desc "Run flay"
task :flay do
  output = `bundle exec flay lib`
  threshold = (ENV["FLAY_THRESHOLD"] || 208).to_i
  score = output[/Total score \(lower is better\) = (\d+)/, 1]&.to_i
  next unless score && score > threshold

  puts "\nFlay failed: Total duplication score is #{score}, must be <= #{threshold}"
  puts output
  exit 1
end

task default: [:test, :standard, :flog, :flay]
