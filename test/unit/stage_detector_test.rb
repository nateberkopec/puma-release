# frozen_string_literal: true

require_relative "../test_helper"

class StageDetectorTest < Minitest::Test
  def test_returns_wait_for_merge_on_release_branch
    detector = build_detector(current_branch: "release-v7.2.1")

    assert_equal :wait_for_merge, detector.next_step
  end

  def test_returns_build_after_release_pr_is_merged_but_before_tag_exists
    detector = build_detector(last_tag: "v7.2.0", current_version: "7.2.1")

    assert_equal :build, detector.next_step
  end

  def test_returns_github_when_release_is_still_pending
    detector = build_detector(release: { "isDraft" => true, "assets" => [] })

    assert_equal :github, detector.next_step
  end

  def test_returns_complete_when_release_is_published_and_there_are_no_new_commits
    detector = build_detector(release: published_release, commits_since: 0)

    assert_equal :complete, detector.next_step
  end

  def test_returns_github_when_release_is_missing_but_tag_is_current
    detector = build_detector(release: nil, commits_since: 0)

    assert_equal :github, detector.next_step
  end

  def test_returns_prepare_when_release_is_missing_and_new_commits_exist
    detector = build_detector(release: nil, commits_since: 3)

    assert_equal :prepare, detector.next_step
  end

  private

  def build_detector(current_branch: "main", last_tag: "v7.2.1", current_version: "7.2.1", release: nil, open_release_pr: nil, commits_since: 0)
    git_repo = Object.new
    git_repo.define_singleton_method(:current_branch) { current_branch }
    git_repo.define_singleton_method(:last_tag) { last_tag }
    git_repo.define_singleton_method(:release_tag) { |version| "v#{version}" }
    git_repo.define_singleton_method(:commits_since) { |_tag| commits_since }

    github = Object.new
    github.define_singleton_method(:open_release_pr) { open_release_pr }
    github.define_singleton_method(:release) { |_tag| release }

    PumaRelease::StageDetector.new(
      OpenStruct.new(shell: FakeShell.new),
      git_repo:,
      repo_files: OpenStruct.new(current_version:),
      github:
    )
  end

  def published_release
    {
      "isDraft" => false,
      "assets" => [
        { "name" => "puma-7.2.1.gem" },
        { "name" => "puma-7.2.1-java.gem" }
      ]
    }
  end
end
