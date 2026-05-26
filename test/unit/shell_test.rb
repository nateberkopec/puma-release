# frozen_string_literal: true

require "stringio"
require_relative "../test_helper"

class ShellTest < Minitest::Test
  def test_shell_env_unbundles_parent_bundle_exec_environment
    shell = PumaRelease::Shell.new(
      env: {
        "PATH" => "/bundle/bin",
        "GEM_HOME" => "/app/vendor/bundle/ruby/4.0.0",
        "BUNDLE_BIN_PATH" => "/ruby/gems/bundler/exe/bundle",
        "BUNDLE_ENTERPRISE__CONTRIBSYS__COM" => "secret",
        "BUNDLE_GEMFILE" => "/app/Gemfile",
        "BUNDLE_LOCKFILE" => "/app/Gemfile.lock",
        "BUNDLER_ORIG_GEM_HOME" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL",
        "BUNDLER_ORIG_PATH" => "/usr/bin:/bin",
        "BUNDLER_VERSION" => "4.0.6"
      },
      cwd: Dir.pwd
    )

    assert_equal "/usr/bin:/bin", shell.env.fetch("PATH")
    assert_equal "secret", shell.env.fetch("BUNDLE_ENTERPRISE__CONTRIBSYS__COM")
    assert_nil shell.env["BUNDLE_BIN_PATH"]
    assert_nil shell.env["BUNDLE_GEMFILE"]
    assert_nil shell.env["BUNDLE_LOCKFILE"]
    assert_nil shell.env["BUNDLER_ORIG_GEM_HOME"]
    assert_nil shell.env["BUNDLER_ORIG_PATH"]
    assert_nil shell.env["BUNDLER_VERSION"]
    assert_nil shell.env["GEM_HOME"]
  end

  def test_shell_env_actually_unsets_parent_bundle_exec_environment_for_child_processes
    shell = PumaRelease::Shell.new(
      env: {
        "PATH" => ENV.fetch("PATH"),
        "BUNDLE_GEMFILE" => "/app/Gemfile",
        "RUBYOPT" => "-rbundler/setup",
        "BUNDLER_ORIG_BUNDLE_GEMFILE" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL",
        "BUNDLER_ORIG_RUBYOPT" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"
      },
      cwd: Dir.pwd
    )

    output = shell.output(Gem.ruby, "-e", "puts ENV.fetch('BUNDLE_GEMFILE', 'unset')")

    assert_equal "unset", output.strip
  end

  def test_stream_output_yields_chunks_without_waiting_for_newline
    shell = PumaRelease::Shell.new(env: {}, cwd: Dir.pwd)
    chunks = []
    times = []
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    original_stdout = $stdout
    $stdout = StringIO.new

    shell.stream_output(
      Gem.ruby, "-e",
      "STDOUT.write('a'); STDOUT.flush; sleep 0.2; STDOUT.write('b'); STDOUT.flush"
    ) do |chunk|
      chunks << chunk
      times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    end

    assert_equal "ab", chunks.join
    assert_operator times.first, :<, 0.18
    assert_operator times.last, :>=, 0.18
  ensure
    $stdout = original_stdout
  end
end
