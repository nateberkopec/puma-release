# frozen_string_literal: true

require_relative "../test_helper"

class GitRepoTest < Minitest::Test
  def test_push_branch_uses_release_repo_remote_when_present
    shell = FakeShell.new(
      {
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    PumaRelease::GitRepo.new(context).push_branch!("release-v7.3.0")

    assert_includes shell.commands, ["git", "push", "-u", "mine", "release-v7.3.0"]
  end

  def test_push_branch_falls_back_to_release_repo_url_when_remote_is_missing
    shell = FakeShell.new(
      {
        ["git", "remote"] => "origin\n",
        ["git", "remote", "get-url", "origin"] => "git@github.com:puma/puma.git\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    PumaRelease::GitRepo.new(context).push_branch!("release-v7.3.0")

    assert_includes shell.commands, ["git", "push", "git@github.com:nateberkopec/puma.git", "release-v7.3.0"]
  end

  def test_ensure_clean_main_prefers_metadata_repo_remote_when_present
    shell = FakeShell.new(
      {
        ["git", "rev-parse", "--abbrev-ref", "HEAD"] => "main\n",
        ["git", "status", "--porcelain"] => "",
        ["git", "remote"] => "origin\nupstream\n",
        ["git", "remote", "get-url", "origin"] => "git@github.com:nateberkopec/puma.git\n",
        ["git", "remote", "get-url", "upstream"] => "https://github.com/puma/puma.git\n",
        ["git", "rev-parse", "upstream/main"] => "abc123\n",
        ["git", "rev-parse", "HEAD"] => "abc123\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    PumaRelease::GitRepo.new(context).ensure_clean_main!

    assert_includes shell.commands, ["git", "fetch", "upstream", "--quiet"]
  end
end
