# frozen_string_literal: true

module PumaRelease
  class UI
    COLORS = {
      info: "\e[0;32m",
      warn: "\e[1;33m",
      error: "\e[0;31m",
      debug: "\e[0;36m",
      reset: "\e[0m"
    }.freeze

    def info(message) = $stdout.puts(colorize(:info, message))
    def warn(message) = $stdout.puts(colorize(:warn, message))
    def error(message) = warn(colorize(:error, message))
    def debug(message) = warn(colorize(:debug, "[DEBUG] #{message}"))

    def confirm(message, default: true)
      return default unless $stdin.tty?

      suffix = default ? "[Y/n]" : "[y/N]"
      $stdout.print("#{message} #{suffix} ")
      answer = $stdin.gets.to_s.strip.downcase
      return default if answer.empty?

      answer.start_with?("y")
    end

    def pause(message)
      return true unless $stdin.tty?

      $stdout.print("#{message} [press enter] ")
      $stdin.gets
      true
    end

    private

    def colorize(kind, message)
      color = COLORS.fetch(kind)
      "#{color}==>#{COLORS.fetch(:reset)} #{message}"
    end
  end
end
