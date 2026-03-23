# frozen_string_literal: true

require "open3"
require "shellwords"

module PumaRelease
  class Shell
    Result = Data.define(:stdout, :stderr, :success?, :exitstatus)

    attr_reader :env, :cwd

    def initialize(env: ENV, cwd: Dir.pwd)
      @env = env.to_h
      @cwd = cwd
    end

    def available?(command)
      return File.file?(command) && File.executable?(command) if command.include?(File::SEPARATOR)

      env.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
        candidate = File.join(path, command)
        File.file?(candidate) && File.executable?(candidate)
      end
    end

    def run(*command, stdin_data: nil, env_overrides: {}, allow_failure: false)
      stdout, stderr, status = Open3.capture3(env.merge(env_overrides), *command, stdin_data:, chdir: cwd)
      result = Result.new(stdout:, stderr:, success?: status.success?, exitstatus: status.exitstatus)
      return result if result.success? || allow_failure

      details = result.stderr.strip
      details = result.stdout.strip if details.empty?
      raise Error, [command.join(" "), details].reject(&:empty?).join(": ")
    end

    def output(*command, **options)
      run(*command, **options).stdout
    end

    def optional_output(*command)
      run(*command, allow_failure: true).stdout.strip
    end

    def split(command)
      Shellwords.split(command)
    end
  end
end
