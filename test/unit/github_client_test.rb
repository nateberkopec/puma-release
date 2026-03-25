# frozen_string_literal: true

require_relative "../test_helper"

class GitHubClientTest < Minitest::Test
  def test_edit_release_target_passes_target_to_gh
    shell = FakeShell.new(
      {
        ["gh", "release", "edit", "v7.3.0", "--repo", "nateberkopec/puma", "--target", "abc123"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["gh", "release", "view", "v7.3.0", "--repo", "nateberkopec/puma", "--json", "tagName,name,isDraft,body,url,assets,targetCommitish"] => FakeShell::Result.new(stdout: '{"tagName":"v7.3.0","targetCommitish":"abc123"}', stderr: "", success?: true, exitstatus: 0)
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma")
    context.define_singleton_method(:confirm_live_github_write!) { |description| confirmations << description }
    release = PumaRelease::GitHubClient.new(context).edit_release_target("v7.3.0", "abc123")

    assert_equal ["retarget release v7.3.0 to abc123"], confirmations
    assert_equal "abc123", release.fetch("targetCommitish")
  end

  def test_edit_release_title_passes_title_to_gh
    shell = FakeShell.new(
      {
        ["gh", "release", "edit", "v7.3.0", "--repo", "nateberkopec/puma", "--title", "v7.3.0 - INSERT CODENAME HERE"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["gh", "release", "view", "v7.3.0", "--repo", "nateberkopec/puma", "--json", "tagName,name,isDraft,body,url,assets,targetCommitish"] => FakeShell::Result.new(stdout: '{"tagName":"v7.3.0","name":"v7.3.0 - INSERT CODENAME HERE"}', stderr: "", success?: true, exitstatus: 0)
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma")
    context.define_singleton_method(:confirm_live_github_write!) { |description| confirmations << description }
    release = PumaRelease::GitHubClient.new(context).edit_release_title("v7.3.0", "v7.3.0 - INSERT CODENAME HERE")

    assert_equal ["edit release title for v7.3.0"], confirmations
    assert_equal "v7.3.0 - INSERT CODENAME HERE", release.fetch("name")
  end

  def test_create_release_pr_confirms_before_writing
    shell = FakeShell.new(
      {
        ["gh", "pr", "create", "--repo", "puma/puma", "--base", "main", "--head", "release-v7.3.0", "--title", "Release v7.3.0", "--body", "compare"] => "https://github.com/puma/puma/pull/1\n"
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "puma/puma")
    context.define_singleton_method(:confirm_live_github_write!) { |description| confirmations << description }

    pr_url = PumaRelease::GitHubClient.new(context).create_release_pr("Release v7.3.0", "release-v7.3.0", body: "compare")

    assert_equal ["create release PR \"Release v7.3.0\""], confirmations
    assert_equal "https://github.com/puma/puma/pull/1", pr_url
  end
end
