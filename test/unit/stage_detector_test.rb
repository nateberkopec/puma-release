# frozen_string_literal: true

require_relative "../test_helper"

class StageDetectorTest < Minitest::Test
  def test_returns_prepare_follow_up_when_a_release_pr_is_open_and_the_prepare_checkpoint_exists
    detector = build_detector(open_release_pr: {"headRefName" => "release-v7.2.1"}, prepare_checkpoint: true)

    assert_equal :prepare_follow_up, detector.next_step
  end

  def test_returns_wait_for_merge_on_release_branch
    detector = build_detector(current_branch: "release-v7.2.1")

    assert_equal :wait_for_merge, detector.next_step
  end

  def test_returns_build_after_release_pr_is_merged_but_before_tag_exists
    detector = build_detector(last_tag: "v7.2.0", current_version: "7.2.1")

    assert_equal :build, detector.next_step
  end

  def test_returns_github_when_release_is_still_pending
    detector = build_detector(release: {"isDraft" => true, "assets" => []})

    assert_equal :github, detector.next_step
  end

  def test_returns_complete_when_release_is_published_and_there_are_no_new_commits
    detector = build_detector(release: published_release, commits_since: 0)

    assert_equal :complete, detector.next_step
  end

  def test_returns_build_when_the_release_is_pending_and_local_artifacts_are_missing
    detector = build_detector(release: nil, commits_since: 0, artifacts_present: false)

    assert_equal :build, detector.next_step
  end

  def test_returns_github_when_release_is_missing_but_tag_is_current_and_local_artifacts_exist
    detector = build_detector(release: nil, commits_since: 0, artifacts_present: true)

    assert_equal :github, detector.next_step
  end

  def test_returns_prepare_when_release_is_missing_and_new_commits_exist
    detector = build_detector(release: nil, commits_since: 3)

    assert_equal :prepare, detector.next_step
  end

  private

  def build_detector(current_branch: "main", last_tag: "v7.2.1", current_version: "7.2.1", release: nil, open_release_pr: nil, commits_since: 0, artifacts_present: true, prepare_checkpoint: false)
    git_repo = Object.new
    git_repo.define_singleton_method(:current_branch) { current_branch }
    git_repo.define_singleton_method(:last_tag) { last_tag }
    git_repo.define_singleton_method(:release_tag) { |version| "v#{version}" }
    git_repo.define_singleton_method(:commits_since) { |_tag| commits_since }

    github = Object.new
    github.define_singleton_method(:open_release_pr) { open_release_pr }
    github.define_singleton_method(:release) { |_tag| release }

    tmp_dir = Pathname(Dir.mktmpdir)
    checkpoint_file = tmp_dir.join("prepare.json")
    checkpoint_file.write("{}") if prepare_checkpoint

    repo_dir = tmp_dir.join("repo")
    pkg_dir = repo_dir.join("pkg")
    pkg_dir.mkpath
    if artifacts_present
      pkg_dir.join("puma-#{current_version}.gem").write("")
      pkg_dir.join("puma-#{current_version}-java.gem").write("")
    end

    PumaRelease::StageDetector.new(
      OpenStruct.new(shell: FakeShell.new, prepare_checkpoint_file: checkpoint_file, repo_dir:),
      git_repo:,
      repo_files: OpenStruct.new(current_version:),
      github:
    )
  end

  def published_release
    {
      "isDraft" => false,
      "assets" => [
        {"name" => "puma-7.2.1.gem"},
        {"name" => "puma-7.2.1-java.gem"}
      ]
    }
  end
end
