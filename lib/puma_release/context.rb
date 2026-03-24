# frozen_string_literal: true

require "json"

module PumaRelease
  class Context
    attr_reader :env, :options, :events, :ui, :shell

    def initialize(options, env: ENV, events: Events.new, ui: UI.new)
      @options = options
      @env = env
      @events = events
      @ui = ui
      @shell = Shell.new(env:, cwd: repo_dir.to_s)
    end

    def repo_dir = options.fetch(:repo_dir)
    def metadata_repo = options.fetch(:metadata_repo)
    def allow_unknown_ci? = options.fetch(:allow_unknown_ci)
    def yes? = options.fetch(:yes)
    def debug? = options.fetch(:debug, false)
    def changelog_backend = env.fetch("PUMA_RELEASE_CHANGELOG_BACKEND", options.fetch(:changelog_backend))
    def agent_cmd = env.fetch("AGENT_CMD", "claude")
    def version_file = repo_dir.join("lib/puma/const.rb")
    def history_file = repo_dir.join("History.md")

    def release_repo
      @release_repo ||= options[:release_repo] || infer_release_repo
    end

    def agent_binary
      shell.split(agent_cmd).first || "claude"
    end

    def github_token
      @github_token ||= begin
        token = env.fetch("GITHUB_TOKEN", "")
        token.empty? ? shell.optional_output("gh", "auth", "token") : token
      end
    end

    def check_dependencies!(*commands)
      missing = commands.flatten.compact.uniq.reject { |command| shell.available?(command) }
      raise Error, "Missing required dependencies: #{missing.join(' ')}" unless missing.empty?
    end

    private

    def infer_release_repo
      url = shell.output("git", "remote", "get-url", "origin").strip
      match = url.match(%r{[:/]([^/]+/[^/.]+?)(?:\.git)?$})
      raise Error, "Could not infer release repo from origin URL: #{url}" unless match

      match[1]
    end
  end
end
