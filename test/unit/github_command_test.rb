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

  def test_ensures_the_signed_tag_is_pushed_before_creating_a_release
    Dir.mktmpdir do |dir|
      repo_dir = Pathname(dir)
      context = OpenStruct.new(
        repo_dir:,
        history_file: repo_dir.join("History.md"),
        events: Object.new,
        ui: Object.new
      )
      context.history_file.write("## 7.2.0 / 2026-01-20\n\n* Bugfixes\n  * One fix ([#1])\n")
      context.define_singleton_method(:check_dependencies!) { |_git, _gh| }
      context.define_singleton_method(:announce_live_mode!) {}
      context.define_singleton_method(:ensure_release_writes_allowed!) {}
      context.events.define_singleton_method(:publish) { |_name, _payload| }
      context.ui.define_singleton_method(:info) { |_message| }

      git_repo = Object.new
      git_repo.define_singleton_method(:ensure_clean_main!) {}
      git_repo.define_singleton_method(:release_tag) { |_version| "v7.2.0" }
      git_repo.define_singleton_method(:ensure_release_tag_pushed!) { |_tag| raise PumaRelease::Error, "stop" }

      repo_files = Object.new
      repo_files.define_singleton_method(:current_version) { "7.2.0" }
      repo_files.define_singleton_method(:extract_history_section) { |_version| "* Bugfixes\n  * One fix ([#1])" }
      repo_files.define_singleton_method(:release_name) { |_version| "v7.2.0" }

      github = Object.new
      github.define_singleton_method(:create_release) { |_tag, _body, title:, draft:| flunk "create_release should not be called before the tag is ensured" }
      github.define_singleton_method(:release) { |_tag| nil }

      command = PumaRelease::Commands::Github.allocate
      command.instance_variable_set(:@context, context)
      command.instance_variable_set(:@git_repo, git_repo)
      command.instance_variable_set(:@repo_files, repo_files)
      command.instance_variable_set(:@github, github)

      repo_dir.join("pkg").mkpath
      repo_dir.join("pkg/puma-7.2.0.gem").write("")
      repo_dir.join("pkg/puma-7.2.0-java.gem").write("")

      error = assert_raises(PumaRelease::Error) { command.call }

      assert_equal "stop", error.message
    end
  end
end
