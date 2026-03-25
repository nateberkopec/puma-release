# frozen_string_literal: true

require_relative "../test_helper"

class GithubCommandTest < Minitest::Test
  def test_checks_git_and_gh_and_requires_a_clean_main_checkout
    calls = []
    context = Object.new
    context.define_singleton_method(:check_dependencies!) { |*commands| calls << commands }
    context.define_singleton_method(:announce_live_mode!) {}
    context.define_singleton_method(:ensure_release_writes_allowed!) {}

    git_repo = Object.new
    git_repo.define_singleton_method(:ensure_clean_main!) { calls << :clean_main }

    repo_files = Object.new
    repo_files.define_singleton_method(:current_version) { raise PumaRelease::Error, "stop" }

    command = PumaRelease::Commands::Github.allocate
    command.instance_variable_set(:@context, context)
    command.instance_variable_set(:@git_repo, git_repo)
    command.instance_variable_set(:@repo_files, repo_files)
    command.instance_variable_set(:@github, Object.new)

    error = assert_raises(PumaRelease::Error) { command.call }

    assert_equal "stop", error.message
    assert_includes calls, ["git", "gh"]
    assert_includes calls, :clean_main
  end
end
