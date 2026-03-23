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

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma")
    release = PumaRelease::GitHubClient.new(context).edit_release_target("v7.3.0", "abc123")

    assert_equal "abc123", release.fetch("targetCommitish")
  end

  def test_edit_release_title_passes_title_to_gh
    shell = FakeShell.new(
      {
        ["gh", "release", "edit", "v7.3.0", "--repo", "nateberkopec/puma", "--title", "v7.3.0 - INSERT CODENAME HERE"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["gh", "release", "view", "v7.3.0", "--repo", "nateberkopec/puma", "--json", "tagName,name,isDraft,body,url,assets,targetCommitish"] => FakeShell::Result.new(stdout: '{"tagName":"v7.3.0","name":"v7.3.0 - INSERT CODENAME HERE"}', stderr: "", success?: true, exitstatus: 0)
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma")
    release = PumaRelease::GitHubClient.new(context).edit_release_title("v7.3.0", "v7.3.0 - INSERT CODENAME HERE")

    assert_equal "v7.3.0 - INSERT CODENAME HERE", release.fetch("name")
  end
end
