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
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }
    release = PumaRelease::GitHubClient.new(context).edit_release_target("v7.3.0", "abc123")

    assert_equal [["gh", "release", "edit", "v7.3.0", "--repo", "nateberkopec/puma", "--target", "abc123"]], confirmations
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
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }
    release = PumaRelease::GitHubClient.new(context).edit_release_title("v7.3.0", "v7.3.0 - INSERT CODENAME HERE")

    assert_equal [["gh", "release", "edit", "v7.3.0", "--repo", "nateberkopec/puma", "--title", "v7.3.0 - INSERT CODENAME HERE"]], confirmations
    assert_equal "v7.3.0 - INSERT CODENAME HERE", release.fetch("name")
  end

  def test_open_release_pr_falls_back_to_a_non_owner_qualified_head_search
    shell = FakeShell.new(
      {
        ["gh", "pr", "list", "--repo", "puma/puma", "--state", "open", "--search", "head:puma:release-v", "--json", "number,title,url,headRefName,baseRefName,mergedAt"] => FakeShell::Result.new(stdout: "[]", stderr: "", success?: true, exitstatus: 0),
        ["gh", "pr", "list", "--repo", "puma/puma", "--state", "open", "--search", "head:release-v", "--json", "number,title,url,headRefName,baseRefName,mergedAt"] => FakeShell::Result.new(stdout: '[{"number":3914,"title":"Release v8.0.0","url":"https://github.com/puma/puma/pull/3914","headRefName":"release-v8.0.0"}]', stderr: "", success?: true, exitstatus: 0)
      }
    )

    context = OpenStruct.new(shell:, release_repo: "puma/puma")

    pr = PumaRelease::GitHubClient.new(context).open_release_pr

    assert_equal 3914, pr.fetch("number")
    assert_equal "release-v8.0.0", pr.fetch("headRefName")
  end

  def test_merged_release_pr_can_find_an_exact_release_branch_and_return_its_base_branch
    shell = FakeShell.new(
      {
        ["gh", "pr", "list", "--repo", "puma/puma", "--state", "merged", "--search", "head:puma:release-v8.0.0", "--json", "number,title,url,headRefName,baseRefName,mergedAt"] => FakeShell::Result.new(stdout: "[]", stderr: "", success?: true, exitstatus: 0),
        ["gh", "pr", "list", "--repo", "puma/puma", "--state", "merged", "--search", "head:release-v8.0.0", "--json", "number,title,url,headRefName,baseRefName,mergedAt"] => FakeShell::Result.new(stdout: '[{"number":3914,"title":"Release v8.0.0","url":"https://github.com/puma/puma/pull/3914","headRefName":"release-v8.0.0","baseRefName":"main","mergedAt":"2026-04-08T23:32:41Z"}]', stderr: "", success?: true, exitstatus: 0)
      }
    )

    context = OpenStruct.new(shell:, release_repo: "puma/puma")

    pr = PumaRelease::GitHubClient.new(context).merged_release_pr("release-v8.0.0")

    assert_equal 3914, pr.fetch("number")
    assert_equal "main", pr.fetch("baseRefName")
  end

  def test_create_release_pr_confirms_before_writing
    shell = FakeShell.new(
      {
        ["gh", "pr", "create", "--repo", "puma/puma", "--base", "main", "--head", "release-v7.3.0", "--title", "Release v7.3.0", "--body", "compare"] => "https://github.com/puma/puma/pull/1\n"
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "puma/puma", base_branch: "main")
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }

    pr_url = PumaRelease::GitHubClient.new(context).create_release_pr("Release v7.3.0", "release-v7.3.0", body: "compare")

    assert_equal [["gh", "pr", "create", "--repo", "puma/puma", "--base", "main", "--head", "release-v7.3.0", "--title", "Release v7.3.0", "--body", "compare"]], confirmations
    assert_equal "https://github.com/puma/puma/pull/1", pr_url
  end

  def test_merge_pr_confirms_before_writing
    shell = FakeShell.new(
      {
        ["gh", "pr", "merge", "https://github.com/puma/puma/pull/1", "--repo", "puma/puma", "--merge", "--delete-branch=false"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0)
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "puma/puma")
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }

    PumaRelease::GitHubClient.new(context).merge_pr("https://github.com/puma/puma/pull/1")

    assert_equal [["gh", "pr", "merge", "https://github.com/puma/puma/pull/1", "--repo", "puma/puma", "--merge", "--delete-branch=false"]], confirmations
  end

  def test_retag_release_updates_the_release_tag_name_via_api
    shell = FakeShell.new(
      {
        ["gh", "api", "repos/nateberkopec/puma/releases/tags/v7.3.0-proposal"] => FakeShell::Result.new(stdout: '{"id":123}', stderr: "", success?: true, exitstatus: 0),
        ["gh", "api", "-X", "PATCH", "repos/nateberkopec/puma/releases/123", "-f", "tag_name=v7.3.0", "-f", "target_commitish=abc123"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["gh", "release", "view", "v7.3.0", "--repo", "nateberkopec/puma", "--json", "tagName,name,isDraft,body,url,assets,targetCommitish"] => FakeShell::Result.new(stdout: '{"tagName":"v7.3.0","targetCommitish":"abc123"}', stderr: "", success?: true, exitstatus: 0)
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma")
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }

    release = PumaRelease::GitHubClient.new(context).retag_release("v7.3.0-proposal", "v7.3.0", target: "abc123")

    assert_equal [["gh", "api", "-X", "PATCH", "repos/nateberkopec/puma/releases/123", "-f", "tag_name=v7.3.0", "-f", "target_commitish=abc123"]], confirmations
    assert_equal "v7.3.0", release.fetch("tagName")
  end

  def test_delete_tag_ref_deletes_a_remote_tag_ref_via_api
    shell = FakeShell.new(
      {
        ["gh", "api", "-X", "DELETE", "repos/nateberkopec/puma/git/refs/tags/v7.3.0-proposal"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0)
      }
    )

    confirmations = []
    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma")
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }

    assert PumaRelease::GitHubClient.new(context).delete_tag_ref("v7.3.0-proposal")
    assert_equal [["gh", "api", "-X", "DELETE", "repos/nateberkopec/puma/git/refs/tags/v7.3.0-proposal"]], confirmations
  end
end
