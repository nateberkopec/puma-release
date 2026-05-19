# frozen_string_literal: true

require_relative "../test_helper"

class GitHubClientReleasePrTest < Minitest::Test
  def test_open_release_pr_prefers_the_current_base_branch
    shell = FakeShell.new(open_release_pr_outputs(
      owner: [release_pr_json(3914, "release-v8.0.0", "main")],
      fallback: [release_pr_json(3920, "release-v7.2.1", "7-2-stable")]
    ))
    context = OpenStruct.new(shell:, release_repo: "puma/puma", base_branch: "7-2-stable")

    pr = PumaRelease::GitHubClient.new(context).open_release_pr

    assert_equal 3920, pr.fetch("number")
    assert_equal "release-v7.2.1", pr.fetch("headRefName")
  end

  def test_open_release_pr_ignores_release_prs_for_other_base_branches
    shell = FakeShell.new(open_release_pr_outputs(owner: [release_pr_json(3914, "release-v8.0.0", "main")]))
    context = OpenStruct.new(shell:, release_repo: "puma/puma", base_branch: "7-2-stable")

    assert_nil PumaRelease::GitHubClient.new(context).open_release_pr
  end

  private

  def open_release_pr_outputs(owner: [], fallback: [])
    {
      pr_list_command("head:puma:release-v") => gh_result(owner),
      pr_list_command("head:release-v") => gh_result(fallback)
    }
  end

  def pr_list_command(query)
    ["gh", "pr", "list", "--repo", "puma/puma", "--state", "open", "--search", query, "--json", "number,title,url,headRefName,baseRefName,mergedAt"]
  end

  def gh_result(items)
    FakeShell::Result.new(stdout: "[#{items.join(",")} ]", stderr: "", success?: true, exitstatus: 0)
  end

  def release_pr_json(number, branch, base)
    <<~JSON.delete("\n")
      {
        "number":#{number},
        "title":"Release #{branch.delete_prefix("release-")}",
        "url":"https://github.com/puma/puma/pull/#{number}",
        "headRefName":"#{branch}",
        "baseRefName":"#{base}"
      }
    JSON
  end
end
