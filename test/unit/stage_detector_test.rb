# frozen_string_literal: true

require_relative "../test_helper"

class StageDetectorTest < Minitest::Test
  def test_returns_wait_for_merge_on_release_branch
    git_repo = Object.new
    def git_repo.current_branch = "release-v7.2.1"
    def git_repo.last_tag = "v7.2.0"
    def git_repo.release_tag(_version) = "v7.2.1"

    github = Object.new
    def github.open_release_pr = nil
    def github.release(_tag) = nil

    detector = PumaRelease::StageDetector.new(
      OpenStruct.new(shell: FakeShell.new),
      git_repo:,
      repo_files: OpenStruct.new(current_version: "7.2.1"),
      github:
    )

    assert_equal :wait_for_merge, detector.next_step
  end

  def test_returns_build_after_release_pr_is_merged_but_before_tag_exists
    git_repo = Object.new
    def git_repo.current_branch = "main"
    def git_repo.last_tag = "v7.2.0"
    def git_repo.release_tag(_version) = "v7.2.1"

    github = Object.new
    def github.open_release_pr = nil
    def github.release(_tag) = nil

    detector = PumaRelease::StageDetector.new(
      OpenStruct.new(shell: FakeShell.new),
      git_repo:,
      repo_files: OpenStruct.new(current_version: "7.2.1"),
      github:
    )

    assert_equal :build, detector.next_step
  end

  def test_returns_github_after_release_tag_exists
    git_repo = Object.new
    def git_repo.current_branch = "main"
    def git_repo.last_tag = "v7.2.1"
    def git_repo.release_tag(_version) = "v7.2.1"

    github = Object.new
    def github.open_release_pr = nil
    def github.release(_tag)
      { "isDraft" => true, "assets" => [] }
    end

    detector = PumaRelease::StageDetector.new(
      OpenStruct.new(shell: FakeShell.new),
      git_repo:,
      repo_files: OpenStruct.new(current_version: "7.2.1"),
      github:
    )

    assert_equal :github, detector.next_step
  end
end
