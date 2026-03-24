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
