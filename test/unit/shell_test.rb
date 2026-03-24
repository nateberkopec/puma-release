# frozen_string_literal: true

require "stringio"
require_relative "../test_helper"

class ShellTest < Minitest::Test
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
    assert_operator times.first, :<, 0.15
    assert_operator times.last, :>=, 0.15
  ensure
    $stdout = original_stdout
  end
end
