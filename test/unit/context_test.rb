# frozen_string_literal: true

require_relative "../test_helper"

class ContextTest < Minitest::Test
  class FakeUI
    attr_reader :warnings, :confirmations
    attr_accessor :confirm_result

    def initialize(confirm_result: true)
      @warnings = []
      @confirmations = []
      @confirm_result = confirm_result
    end

    def warn(message)
      warnings << message
    end

    def confirm(message, default: true)
      confirmations << [message, default]
      confirm_result
    end
  end

  def test_base_branch_uses_the_remembered_release_branch_base
    shell = FakeShell.new(
      {
        ["git", "rev-parse", "--abbrev-ref", "HEAD"] => "release-v8.0.0\n",
        ["git", "config", "--get", "branch.release-v8.0.0.puma-release-base"] => "main\n"
      }
    )

    context = build_context(shell:, live: true)

    assert_equal "main", context.base_branch
  end

  def test_base_branch_uses_the_merged_release_pr_base_when_the_remembered_base_is_missing
    shell = FakeShell.new(
      {
        ["git", "rev-parse", "--abbrev-ref", "HEAD"] => "release-v8.0.0\n",
        ["git", "config", "--get", "branch.release-v8.0.0.puma-release-base"] => "",
        ["gh", "pr", "list", "--repo", "puma/puma", "--state", "merged", "--search", "head:puma:release-v8.0.0", "--json", "number,title,url,headRefName,baseRefName,mergedAt"] => FakeShell::Result.new(stdout: "[]", stderr: "", success?: true, exitstatus: 0),
        ["gh", "pr", "list", "--repo", "puma/puma", "--state", "merged", "--search", "head:release-v8.0.0", "--json", "number,title,url,headRefName,baseRefName,mergedAt"] => FakeShell::Result.new(stdout: '[{"number":3914,"headRefName":"release-v8.0.0","baseRefName":"main"}]', stderr: "", success?: true, exitstatus: 0)
      }
    )

    context = build_context(shell:, live: true)

    assert_equal "main", context.base_branch
  end

  def test_release_repo_prefers_a_fork_remote_when_not_live
    shell = FakeShell.new(
      {
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = build_context(shell:, live: false)

    assert_equal "nateberkopec/puma", context.release_repo
  end

  def test_release_repo_defaults_to_metadata_repo_in_live_mode
    shell = FakeShell.new(
      {
        ["git", "remote"] => "origin\nmine\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["git", "remote", "get-url", "mine"] => "git@github.com:nateberkopec/puma.git\n"
      }
    )

    context = build_context(shell:, live: true)

    assert_equal "puma/puma", context.release_repo
  end

  def test_refuses_writes_to_metadata_repo_without_live
    shell = FakeShell.new
    context = build_context(shell:, live: false, release_repo: "puma/puma")

    error = assert_raises(PumaRelease::Error) { context.ensure_release_writes_allowed! }

    assert_includes error.message, "without --live"
  end

  def test_release_repo_prefers_the_authenticated_users_fork_when_multiple_candidates_exist
    shell = FakeShell.new(
      {
        ["git", "remote"] => "backup\norigin\nupstream\n",
        ["git", "remote", "get-url", "backup"] => "git@github.com:someoneelse/puma.git\n",
        ["git", "remote", "get-url", "origin"] => "git@github.com:nateberkopec/puma.git\n",
        ["git", "remote", "get-url", "upstream"] => "https://github.com/puma/puma.git\n",
        ["gh", "api", "user"] => FakeShell::Result.new(stdout: '{"login":"nateberkopec"}', stderr: "", success?: true, exitstatus: 0)
      }
    )

    context = build_context(shell:, live: false)

    assert_equal "nateberkopec/puma", context.release_repo
  end

  def test_release_repo_falls_back_to_metadata_repo_when_fork_is_ambiguous
    shell = FakeShell.new(
      {
        ["git", "remote"] => "backup\nmirror\norigin\n",
        ["git", "remote", "get-url", "backup"] => "git@github.com:someoneelse/puma.git\n",
        ["git", "remote", "get-url", "mirror"] => "git@github.com:anotheruser/puma.git\n",
        ["git", "remote", "get-url", "origin"] => "https://github.com/puma/puma.git\n",
        ["gh", "api", "user"] => FakeShell::Result.new(stdout: '{"login":"nateberkopec"}', stderr: "", success?: true, exitstatus: 0)
      }
    )

    context = build_context(shell:, live: false)

    assert_equal "puma/puma", context.release_repo
  end

  def test_announce_live_mode_warns_once
    shell = FakeShell.new
    ui = FakeUI.new
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    context.announce_live_mode!
    context.announce_live_mode!

    assert_equal ["LIVE MODE: writes will go to puma/puma"], ui.warnings
  end

  def test_confirm_live_github_write_prompts_in_live_mode
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: true)
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    assert context.confirm_live_github_write!("publish release v7.3.0")
    assert_equal [["LIVE MODE: publish release v7.3.0 on GitHub for puma/puma. Continue?", true]], ui.confirmations
  end

  def test_confirm_live_github_write_raises_when_declined
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: false)
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    error = assert_raises(PumaRelease::Error) { context.confirm_live_github_write!("publish release v7.3.0") }

    assert_includes error.message, "Aborted live GitHub action"
  end

  def test_confirm_live_github_write_skips_prompt_when_not_live
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: false)
    context = build_context(shell:, live: false, release_repo: "nateberkopec/puma", ui:)

    assert context.confirm_live_github_write!("publish release v7.3.0")
    assert_empty ui.confirmations
  end

  def test_confirm_live_github_write_skips_prompt_when_yes_is_set
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: false)
    context = build_context(shell:, live: true, release_repo: "puma/puma", yes: true, ui:)

    assert context.confirm_live_github_write!("publish release v7.3.0")
    assert_empty ui.confirmations
  end

  def test_confirm_live_git_command_prompts_in_live_mode_with_the_full_command
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: true)
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    assert context.confirm_live_git_command!("git", "push", "origin", "main")
    assert_equal [["LIVE MODE: about to run git command: git push origin main. Continue?", true]], ui.confirmations
  end

  def test_confirm_live_git_command_raises_when_declined
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: false)
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    error = assert_raises(PumaRelease::Error) { context.confirm_live_git_command!("git", "push", "origin", "main") }

    assert_includes error.message, "Aborted live git action"
  end

  def test_confirm_live_git_command_skips_prompt_when_yes_is_set
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: false)
    context = build_context(shell:, live: true, release_repo: "puma/puma", yes: true, ui:)

    assert context.confirm_live_git_command!("git", "push", "origin", "main")
    assert_empty ui.confirmations
  end

  def test_confirm_live_gh_command_prompts_in_live_mode_with_the_full_command
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: true)
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    assert context.confirm_live_gh_command!("gh", "release", "edit", "v7.3.0", "--repo", "puma/puma", "--draft=false")
    assert_equal [["LIVE MODE: about to run gh command: gh release edit v7.3.0 --repo puma/puma --draft\\=false. Continue?", true]], ui.confirmations
  end

  def test_confirm_live_gh_command_raises_when_declined
    shell = FakeShell.new
    ui = FakeUI.new(confirm_result: false)
    context = build_context(shell:, live: true, release_repo: "puma/puma", ui:)

    error = assert_raises(PumaRelease::Error) { context.confirm_live_gh_command!("gh", "release", "edit", "v7.3.0", "--repo", "puma/puma", "--draft=false") }

    assert_includes error.message, "Aborted live gh action"
  end

  private

  def build_context(shell:, live:, release_repo: nil, yes: false, ui: PumaRelease::UI.new)
    options = {
      command: "run",
      repo_dir: Pathname(Dir.pwd),
      metadata_repo: "puma/puma",
      release_repo:,
      changelog_backend: "auto",
      allow_unknown_ci: false,
      yes:,
      live:,
      debug: false
    }

    context = PumaRelease::Context.new(options, env: {}, ui:)
    context.instance_variable_set(:@shell, shell)
    context
  end
end
