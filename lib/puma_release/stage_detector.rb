# frozen_string_literal: true

module PumaRelease
  class StageDetector
    attr_reader :context, :git_repo, :repo_files, :github

    def initialize(context, git_repo: GitRepo.new(context), repo_files: RepoFiles.new(context), github: GitHubClient.new(context))
      @context = context
      @git_repo = git_repo
      @repo_files = repo_files
      @github = github
    end

    def next_step
      return :wait_for_merge if waiting_on_release_pr?
      return :build if repo_files.current_version != git_repo.last_tag.delete_prefix("v")
      return :github if github_release_pending?

      :prepare
    end

    private

    def waiting_on_release_pr?
      return true if git_repo.current_branch.start_with?("release-v")

      !github.open_release_pr.nil?
    end

    def github_release_pending?
      release = github.release(git_repo.release_tag(repo_files.current_version))
      return false unless release

      assets = Array(release["assets"]).map { |asset| asset["name"] }
      expected = ["puma-#{repo_files.current_version}.gem", "puma-#{repo_files.current_version}-java.gem"]
      release.fetch("isDraft", false) || (expected - assets).any?
    end
  end
end
