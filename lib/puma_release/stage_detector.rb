# frozen_string_literal: true

module PumaRelease
  class StageDetector
    attr_reader :context, :git_repo, :repo_files, :github, :rubygems

    def initialize(context, git_repo: GitRepo.new(context), repo_files: RepoFiles.new(context), github: GitHubClient.new(context), rubygems: RubyGemsClient.new(context))
      @context = context
      @git_repo = git_repo
      @repo_files = repo_files
      @github = github
      @rubygems = rubygems
    end

    def next_step
      return :recover_prepare if recoverable_orphaned_release_branch?
      return :orphaned_release_branch if orphaned_release_branch?
      return :prepare_follow_up if prepare_follow_up_pending?
      return :recover_build if recoverable_merged_release_branch?
      return :wait_for_merge if waiting_on_release_pr?
      return :build if release_version_ahead_of_tag?
      return :build if build_artifacts_missing_for_pending_release?
      return :wait_for_rubygems if waiting_for_rubygems?
      return :github if github_release_pending?
      return :github if github_release_missing_for_current_tag?
      return :github if proposal_cleanup_pending?
      return :complete if no_new_commits_since_last_release?

      :prepare
    end

    private

    def waiting_on_release_pr?
      return current_branch_release_pr_open? if git_repo.current_branch.start_with?("release-v")

      release_pr_in_flight?
    end

    def current_branch_release_pr_open?
      pr = open_release_pr
      pr && pr.fetch("headRefName", "") == git_repo.current_branch
    end

    def release_pr_in_flight?
      pr = open_release_pr
      return false unless pr

      version = release_pr_version(pr)
      return false unless version

      proposal_release = github.release(git_repo.proposal_tag(version))
      proposal_release && proposal_release.fetch("targetCommitish", "") == pr.fetch("headRefName", "")
    end

    def prepare_follow_up_pending?
      !open_release_pr.nil? && context.prepare_checkpoint_file.file?
    end

    def recoverable_orphaned_release_branch?
      orphaned_release_branch? && !git_repo.release_branch_base.empty?
    end

    def recoverable_merged_release_branch?
      git_repo.current_branch.start_with?("release-v") &&
        open_release_pr.nil? &&
        !merged_release_pr_for_current_branch.nil? &&
        release_version_ahead_of_tag?
    end

    def orphaned_release_branch?
      git_repo.current_branch.start_with?("release-v") &&
        github.open_release_pr.nil? &&
        !release_version_ahead_of_tag?
    end

    def release_version_ahead_of_tag?
      repo_files.current_version != git_repo.last_tag.delete_prefix("v")
    end

    def github_release_pending?
      release = current_release
      return false unless release

      release.fetch("isDraft", false) || missing_assets?(release)
    end

    def build_artifacts_missing_for_pending_release?
      return false if release_complete?

      !build_artifacts_present? && (current_release.nil? || github_release_pending?)
    end

    def waiting_for_rubygems?
      return false if release_complete?
      return false unless build_artifacts_present?
      return false unless current_release.nil? || github_release_pending?

      !rubygems.release_published?(repo_files.current_version)
    end

    def github_release_missing_for_current_tag?
      current_release.nil? && no_new_commits_since_last_release?
    end

    def no_new_commits_since_last_release?
      git_repo.commits_since(git_repo.last_tag).zero?
    end

    def proposal_cleanup_pending?
      return false unless no_new_commits_since_last_release?
      return false unless current_release && !github_release_pending?

      proposal_tag = git_repo.proposal_tag(repo_files.current_version)
      github.release(proposal_tag) || !git_repo.remote_tag_sha(proposal_tag).empty?
    end

    def release_pr_version(pr)
      branch = pr.fetch("headRefName", "")
      branch.delete_prefix("release-v") if branch.start_with?("release-v")
    end

    def open_release_pr
      return @open_release_pr if defined?(@open_release_pr)

      @open_release_pr = github.open_release_pr
    end

    def merged_release_pr_for_current_branch
      return @merged_release_pr_for_current_branch if defined?(@merged_release_pr_for_current_branch)

      @merged_release_pr_for_current_branch = github.merged_release_pr(git_repo.current_branch)
    end

    def current_release
      return @current_release if defined?(@current_release)

      @current_release = github.release(git_repo.release_tag(repo_files.current_version))
    end

    def release_complete?
      release = current_release
      release && !release.fetch("isDraft", false) && !missing_assets?(release)
    end

    def build_artifacts_present?
      expected_assets.all? { |name| context.repo_dir.join("pkg", name).file? }
    end

    def missing_assets?(release)
      assets = Array(release["assets"]).map { |asset| asset["name"] }
      (expected_assets - assets).any?
    end

    def expected_assets
      ["puma-#{repo_files.current_version}.gem", "puma-#{repo_files.current_version}-java.gem"]
    end
  end
end
