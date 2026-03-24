# frozen_string_literal: true

require "json"
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

    def stream_output(*command, stdin_data: nil, env_overrides: {})
      stdout_buffer = +""
      stderr_buffer = +""

      Open3.popen3(env.merge(env_overrides), *command, chdir: cwd) do |stdin, stdout, stderr, wait_thr|
        stdin.write(stdin_data) if stdin_data
        stdin.close

        stdout_thread = Thread.new do
          stream_chunks(stdout) do |chunk|
            $stdout.print(chunk)
            $stdout.flush
            stdout_buffer << chunk
            yield chunk if block_given?
          end
        end

        stderr_thread = Thread.new do
          stream_chunks(stderr) { |chunk| stderr_buffer << chunk }
        end

        stdout_thread.join
        stderr_thread.join
        status = wait_thr.value
        return stdout_buffer if status.success?

        details = stderr_buffer.strip
        details = stdout_buffer.strip if details.empty?
        raise Error, [command.join(" "), details].reject(&:empty?).join(": ")
      end
    end

    def stream_json_events(*command, stdin_data: nil, env_overrides: {})
      Open3.popen3(env.merge(env_overrides), *command, chdir: cwd) do |stdin, stdout, stderr, wait_thr|
        stdin.write(stdin_data) if stdin_data
        stdin.close
        stdout.each_line do |line|
          next if line.strip.empty?
          begin
            yield JSON.parse(line)
          rescue JSON::ParserError
          end
        end
        status = wait_thr.value
        raise Error, command.join(" ") unless status.success?
      end
    end

    def optional_output(*command)
      run(*command, allow_failure: true).stdout.strip
    end

    def split(command)
      Shellwords.split(command)
    end

    private

    def stream_chunks(io)
      loop do
        chunk = io.readpartial(1024)
        yield chunk
      end
    rescue EOFError
    end
  end
end
