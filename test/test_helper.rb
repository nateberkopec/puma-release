# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "pathname"
require "ostruct"
require_relative "../lib/puma_release"

module TestSupport
  class FakeShell
    Result = Data.define(:stdout, :stderr, :success?, :exitstatus)

    attr_reader :commands

    def initialize(outputs = {})
      @outputs = outputs
      @commands = []
    end

    def output(*command, **_options)
      commands << command
      value = @outputs.fetch(command, "")
      value.respond_to?(:call) ? value.call : value
    end

    def run(*command, allow_failure: false, **_options)
      commands << command
      value = @outputs.fetch(command, Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0))
      value = value.call if value.respond_to?(:call)
      return value if value.success? || allow_failure

      raise PumaRelease::Error, command.join(" ")
    end

    def optional_output(*command)
      output(*command)
    end

    def available?(_command)
      true
    end

    def split(command)
      command.split
    end
  end

  def temp_repo
    Dir.mktmpdir do |dir|
      repo = Pathname(dir)
      repo.join("lib/puma").mkpath
      yield repo
    end
  end
end

class Minitest::Test
  include TestSupport
end
