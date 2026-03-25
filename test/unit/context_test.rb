# frozen_string_literal: true

require_relative "../test_helper"

class ContextTest < Minitest::Test
  class FakeUI
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message)
      warnings << message
    end
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

  private

  def build_context(shell:, live:, release_repo: nil, ui: PumaRelease::UI.new)
    options = {
      command: "run",
      repo_dir: Pathname(Dir.pwd),
      metadata_repo: "puma/puma",
      release_repo:,
      changelog_backend: "auto",
      allow_unknown_ci: false,
      yes: false,
      live:,
      debug: false
    }

    context = PumaRelease::Context.new(options, env: {}, ui:)
    context.instance_variable_set(:@shell, shell)
    context
  end
end
