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
    git_repo.define_singleton_method(:ensure_clean_base!) { calls << :clean_main }

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
      git_repo.define_singleton_method(:ensure_clean_base!) {}
      git_repo.define_singleton_method(:release_tag) { |_version| "v7.2.0" }
      git_repo.define_singleton_method(:proposal_tag) { |_version| "v7.2.0-proposal" }
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

  def test_promotes_the_proposal_release_to_the_final_tag
    Dir.mktmpdir do |dir|
      repo_dir = Pathname(dir)
      context = OpenStruct.new(
        repo_dir:,
        history_file: repo_dir.join("History.md"),
        events: Object.new,
        ui: Object.new
      )
      context.history_file.write("## 7.2.0 / 2026-01-20\n\n* Bugfixes\n  * One fix ([#1])\n")
      published = []
      infos = []
      context.define_singleton_method(:check_dependencies!) { |_git, _gh| }
      context.define_singleton_method(:announce_live_mode!) {}
      context.define_singleton_method(:ensure_release_writes_allowed!) {}
      context.events.define_singleton_method(:publish) { |name, payload| published << [name, payload] }
      context.ui.define_singleton_method(:info) { |message| infos << message }

      git_repo = Object.new
      git_repo.define_singleton_method(:ensure_clean_base!) {}
      git_repo.define_singleton_method(:release_tag) { |_version| "v7.2.0" }
      git_repo.define_singleton_method(:proposal_tag) { |_version| "v7.2.0-proposal" }
      git_repo.define_singleton_method(:ensure_release_tag_pushed!) { |_tag| }
      git_repo.define_singleton_method(:local_tag_sha) { |_tag| "abc123" }
      git_repo.define_singleton_method(:remote_tag_sha) { |_tag| "proposal123" }

      repo_files = Object.new
      repo_files.define_singleton_method(:current_version) { "7.2.0" }
      repo_files.define_singleton_method(:extract_history_section) { |_version| "* Bugfixes\n  * One fix ([#1])" }
      repo_files.define_singleton_method(:release_name) { |_version| "v7.2.0" }

      calls = []
      github = Object.new
      github.define_singleton_method(:release) do |tag|
        case tag
        when "v7.2.0" then nil
        when "v7.2.0-proposal" then { "isDraft" => true, "targetCommitish" => "release-v7.2.0", "name" => "v7.2.0", "body" => "* Bugfixes\n  * One fix ([#1])", "url" => "https://example.test/release" }
        end
      end
      github.define_singleton_method(:retag_release) do |old_tag, new_tag, target:|
        calls << [:retag_release, old_tag, new_tag, target]
        { "isDraft" => true, "targetCommitish" => target, "name" => "v7.2.0", "body" => "* Bugfixes\n  * One fix ([#1])", "url" => "https://example.test/release" }
      end
      github.define_singleton_method(:edit_release_target) { |_tag, _target| flunk "edit_release_target should not be called when retag_release already set the final target" }
      github.define_singleton_method(:edit_release_title) { |_tag, _title| flunk "edit_release_title should not be called when the release title already matches" }
      github.define_singleton_method(:edit_release_notes) { |_tag, _body| flunk "edit_release_notes should not be called when the release notes already match" }
      github.define_singleton_method(:upload_release_assets) { |tag, *paths| calls << [:upload_release_assets, tag, paths.map { |path| File.basename(path) }] }
      github.define_singleton_method(:publish_release) do |tag|
        calls << [:publish_release, tag]
        { "isDraft" => false, "url" => "https://example.test/release" }
      end
      github.define_singleton_method(:delete_release) { |_tag, allow_failure:| calls << [:delete_release, allow_failure] }
      github.define_singleton_method(:delete_tag_ref) { |tag, allow_failure:| calls << [:delete_tag_ref, tag, allow_failure] }
      github.define_singleton_method(:create_release) { |_tag, _body, title:, draft:| flunk "create_release should not be called when a proposal release already exists" }

      command = PumaRelease::Commands::Github.allocate
      command.instance_variable_set(:@context, context)
      command.instance_variable_set(:@git_repo, git_repo)
      command.instance_variable_set(:@repo_files, repo_files)
      command.instance_variable_set(:@github, github)

      repo_dir.join("pkg").mkpath
      repo_dir.join("pkg/puma-7.2.0.gem").write("")
      repo_dir.join("pkg/puma-7.2.0-java.gem").write("")

      assert_equal :complete, command.call
      assert_includes infos, "Promoting draft release from v7.2.0-proposal to v7.2.0..."
      assert_includes calls, [:retag_release, "v7.2.0-proposal", "v7.2.0", "abc123"]
      assert_includes calls, [:upload_release_assets, "v7.2.0", ["puma-7.2.0.gem", "puma-7.2.0-java.gem"]]
      assert_includes calls, [:publish_release, "v7.2.0"]
      assert_includes calls, [:delete_tag_ref, "v7.2.0-proposal", true]
      assert_equal [[:release_published, { tag: "v7.2.0", url: "https://example.test/release" }]], published
    end
  end
end
