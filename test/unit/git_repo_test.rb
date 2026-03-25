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

  def test_commit_release_creates_a_signed_commit
    temp_repo do |repo|
      version_file = repo.join("lib/puma/const.rb")
      history_file = repo.join("History.md")
      version_file.write("")
      history_file.write("")
      shell = FakeShell.new
      context = OpenStruct.new(shell:, version_file:, history_file:)

      PumaRelease::GitRepo.new(context).commit_release!("7.3.0")

      assert_includes shell.commands, ["git", "commit", "-S", "-m", "Release v7.3.0"]
    end
  end

  def test_ensure_release_tag_pushed_creates_a_signed_tag
    shell = FakeShell.new(
      {
        ["git", "rev-parse", "HEAD"] => "abc123\n",
        ["git", "ls-remote", "--tags", "mine", "refs/tags/v7.3.0", "refs/tags/v7.3.0^{}"] => "",
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    PumaRelease::GitRepo.new(context).ensure_release_tag_pushed!("v7.3.0")

    assert_includes shell.commands, ["git", "tag", "-s", "v7.3.0", "-m", "Release v7.3.0"]
  end

  def test_remote_tag_sha_returns_the_peeled_commit_for_signed_tags
    shell = FakeShell.new(
      {
        ["git", "ls-remote", "--tags", "mine", "refs/tags/v7.3.0", "refs/tags/v7.3.0^{}"] => [
          "deadbeef\trefs/tags/v7.3.0",
          "abc123\trefs/tags/v7.3.0^{}"
        ].join("\n"),
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    assert_equal "abc123", PumaRelease::GitRepo.new(context).remote_tag_sha("v7.3.0")
  end

  def test_ensure_release_tag_pushed_rejects_an_unsigned_local_tag
    shell = FakeShell.new(
      {
        ["git", "rev-parse", "HEAD"] => "abc123\n",
        ["git", "rev-parse", "-q", "--verify", "refs/tags/v7.3.0^{commit}"] => "abc123\n",
        ["git", "ls-remote", "--tags", "mine", "refs/tags/v7.3.0", "refs/tags/v7.3.0^{}"] => "",
        ["git", "cat-file", "-p", "refs/tags/v7.3.0"] => "tree deadbeef\nauthor Example <example@test> 0 +0000\n\nnot signed\n",
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    error = assert_raises(PumaRelease::Error) { PumaRelease::GitRepo.new(context).ensure_release_tag_pushed!("v7.3.0") }

    assert_includes error.message, "is not GPG-signed"
  end

  def test_ensure_release_tag_pushed_rejects_a_remote_tag_that_differs_from_the_local_signed_tag
    shell = FakeShell.new(
      {
        ["git", "rev-parse", "HEAD"] => "abc123\n",
        ["git", "rev-parse", "-q", "--verify", "refs/tags/v7.3.0^{commit}"] => "abc123\n",
        ["git", "rev-parse", "-q", "--verify", "refs/tags/v7.3.0"] => "localtag\n",
        ["git", "ls-remote", "--tags", "mine", "refs/tags/v7.3.0", "refs/tags/v7.3.0^{}"] => [
          "remotetag\trefs/tags/v7.3.0",
          "abc123\trefs/tags/v7.3.0^{}"
        ].join("\n"),
        ["git", "ls-remote", "--tags", "mine", "refs/tags/v7.3.0"] => "remotetag\trefs/tags/v7.3.0\n",
        ["git", "cat-file", "-p", "refs/tags/v7.3.0"] => "object abc123\ntype commit\ntag v7.3.0\n\n-----BEGIN PGP SIGNATURE-----\n",
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = OpenStruct.new(shell:, release_repo: "nateberkopec/puma", metadata_repo: "puma/puma")

    error = assert_raises(PumaRelease::Error) { PumaRelease::GitRepo.new(context).ensure_release_tag_pushed!("v7.3.0") }

    assert_includes error.message, "does not match the local signed tag"
  end
end
