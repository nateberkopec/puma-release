# frozen_string_literal: true

require "json"
require "shellwords"

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
    def skip_ci_check? = options.fetch(:skip_ci_check, false)
    def yes? = options.fetch(:yes)
    def live? = options.fetch(:live, false)
    def debug? = options.fetch(:debug, false) || env["DEBUG"] == "true"
    def changelog_backend = env.fetch("PUMA_RELEASE_CHANGELOG_BACKEND", options.fetch(:changelog_backend))
    def codename = options.fetch(:codename)

    def base_branch
      @base_branch ||= options[:base_branch] || inferred_base_branch
    end

    def agent_cmd = env.fetch("AGENT_CMD", "claude")
    TOOL_URL = "https://github.com/nateberkopec/puma-release"

    def version_file = repo_dir.join("lib/puma/const.rb")
    def history_file = repo_dir.join("History.md")
    def security_file = repo_dir.join("SECURITY.md")
    def prepare_checkpoint_file = repo_dir.join(".git", "puma-release", "prepare.json")

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
      raise Error, "Missing required dependencies: #{missing.join(" ")}" unless missing.empty?
    end

    def comment_author_model_name(fallback: env["AGENT_MODEL_NAME"])
      value = fallback.to_s.strip
      return value unless value.empty?

      agent_binary
    end

    def comment_attribution(model_name)
      "This comment was written by #{model_name} working on behalf of [puma-release](#{TOOL_URL})."
    end

    def announce_live_mode!
      return unless live?
      return if @live_mode_announced

      ui.warn("LIVE MODE: writes will go to #{release_repo}")
      @live_mode_announced = true
    end

    def ensure_release_writes_allowed!
      return if live?
      return unless release_repo == metadata_repo

      raise Error,
        "Refusing to write release state to #{release_repo} without --live. " \
        "Use --release-repo OWNER/REPO to target a fork, or pass --live to operate on #{metadata_repo}."
    end

    def confirm_live_github_write!(description)
      return true unless live?
      return true if yes?
      return true if ui.confirm("LIVE MODE: #{description} on GitHub for #{release_repo}. Continue?")

      raise Error, "Aborted live GitHub action: #{description}"
    end

    def confirm_live_git_command!(*command)
      return true unless live?
      return true if yes?

      rendered = Shellwords.join(command)
      return true if ui.confirm("LIVE MODE: about to run git command: #{rendered}. Continue?")

      raise Error, "Aborted live git action: #{rendered}"
    end

    def confirm_live_gh_command!(*command)
      return true unless live?
      return true if yes?

      rendered = Shellwords.join(command)
      return true if ui.confirm("LIVE MODE: about to run gh command: #{rendered}. Continue?")

      raise Error, "Aborted live gh action: #{rendered}"
    end

    private

    def inferred_base_branch
      current = shell.output("git", "rev-parse", "--abbrev-ref", "HEAD").strip
      return current unless current.start_with?("release-v")

      remembered = shell.optional_output("git", "config", "--get", "branch.#{current}.puma-release-base")
      return remembered unless remembered.empty?

      merged_pr_base_branch(current) || default_branch_for(metadata_repo) || current
    end

    def infer_release_repo
      return metadata_repo if live?

      preferred_fork_repo || metadata_repo
    end

    def preferred_fork_repo
      candidates = github_remotes.reject { |_remote, repo| repo == metadata_repo }
      return candidates.first&.last if candidates.one?

      login_match = candidates.find { |_remote, repo| repo_owner(repo) == github_login }
      return login_match.last if login_match

      origin_match = candidates.find { |remote, _repo| remote == "origin" }
      origin_match&.last
    end

    def github_login
      return @github_login if defined?(@github_login)

      @github_login = fetch_github_login
    end

    def repo_owner(repo)
      repo.split("/", 2).first
    end

    def fetch_github_login
      return nil unless shell.available?("gh")

      result = shell.run("gh", "api", "user", allow_failure: true)
      return nil unless result.success?

      login = JSON.parse(result.stdout).fetch("login", "").strip
      login.empty? ? nil : login
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def merged_pr_base_branch(branch)
      GitHubClient.new(self).merged_release_pr(branch)&.fetch("baseRefName", nil).to_s.strip.then do |base|
        base.empty? ? nil : base
      end
    end

    def default_branch_for(repo)
      return nil unless shell.available?("gh")

      result = shell.run("gh", "api", "repos/#{repo}", allow_failure: true)
      return nil unless result.success?

      branch = JSON.parse(result.stdout).fetch("default_branch", "").strip
      branch.empty? ? nil : branch
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def github_remotes
      shell.output("git", "remote").lines(chomp: true).filter_map do |remote|
        repo = github_repo_from_url(shell.output("git", "remote", "get-url", remote).strip)
        repo ? [remote, repo] : nil
      end
    end

    def github_repo_from_url(url)
      url[%r{github\.com[:/]([^/]+/[^/.]+?)(?:\.git)?$}, 1]
    end
  end
end
