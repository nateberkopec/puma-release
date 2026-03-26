# frozen_string_literal: true

require_relative "../test_helper"

class ContributorResolverTest < Minitest::Test
  def test_resolves_github_login_from_commit_metadata
    shell = FakeShell.new(
      {
        ["git", "shortlog", "-s", "-n", "-e", "--no-merges", "v7.2.0..HEAD"] => "    10\tNate Berkopec <nate.berkopec@gmail.com>\n",
        ["git", "log", "--format=%H%x09%aN%x09%aE", "v7.2.0..HEAD"] => [
          "abc123\tNate Berkopec\tnate.berkopec@gmail.com",
          "def456\tNate Berkopec\tnate.berkopec@gmail.com"
        ].join("\n")
      }
    )

    context = OpenStruct.new(metadata_repo: "puma/puma")
    git_repo = PumaRelease::GitRepo.new(OpenStruct.new(shell:))
    github = Object.new
    def github.commit_author_login(_repo, sha)
      {"abc123" => "nateberkopec", "def456" => "nateberkopec"}.fetch(sha)
    end

    earner = PumaRelease::ContributorResolver.new(context, git_repo:, github:).codename_earner("v7.2.0")

    assert_equal "Nate Berkopec", earner.fetch(:name)
    assert_equal "nateberkopec", earner.fetch(:login)
  end

  def test_falls_back_to_github_noreply_email_login
    shell = FakeShell.new(
      {
        ["git", "shortlog", "-s", "-n", "-e", "--no-merges", "v7.2.0..HEAD"] => "    1\tYuki Nishijima <386234+yuki24@users.noreply.github.com>\n",
        ["git", "log", "--format=%H%x09%aN%x09%aE", "v7.2.0..HEAD"] => "abc123\tYuki Nishijima\t386234+yuki24@users.noreply.github.com"
      }
    )

    context = OpenStruct.new(metadata_repo: "puma/puma")
    git_repo = PumaRelease::GitRepo.new(OpenStruct.new(shell:))
    github = Object.new
    def github.commit_author_login(_repo, _sha) = nil

    earner = PumaRelease::ContributorResolver.new(context, git_repo:, github:).codename_earner("v7.2.0")

    assert_equal "yuki24", earner.fetch(:login)
  end
end
