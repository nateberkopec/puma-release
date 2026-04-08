# frozen_string_literal: true

require_relative "../test_helper"

class PrepareTest < Minitest::Test
  class FakeUI
    attr_reader :infos, :warnings

    def initialize
      @infos = []
      @warnings = []
    end

    def info(message)
      infos << message
    end

    def warn(message)
      warnings << message
    end
  end

  def test_ensure_green_ci_skips_when_flag_is_set
    ui = FakeUI.new
    context = OpenStruct.new(skip_ci_check?: true, ui:)
    git_repo = OpenStruct.new(head_sha: "abc123")
    prepare = PumaRelease::Commands::Prepare.allocate
    prepare.instance_variable_set(:@context, context)
    prepare.instance_variable_set(:@git_repo, git_repo)

    checker = Object.new
    def checker.ensure_green!(_sha)
      flunk "CiChecker should not be called when CI is skipped"
    end
    prepare.define_singleton_method(:ci_checker) { checker }

    prepare.send(:ensure_green_ci!)

    assert_equal ["Skipping CI check because --skip-ci-check was set."], ui.warnings
    assert_empty ui.infos
  end

  def test_ensure_green_ci_checks_head_when_flag_is_not_set
    ui = FakeUI.new
    context = OpenStruct.new(skip_ci_check?: false, ui:)
    git_repo = OpenStruct.new(head_sha: "abc123")
    prepare = PumaRelease::Commands::Prepare.allocate
    prepare.instance_variable_set(:@context, context)
    prepare.instance_variable_set(:@git_repo, git_repo)

    checker = Object.new
    calls = []
    checker.define_singleton_method(:ensure_green!) { |sha| calls << sha }
    prepare.define_singleton_method(:ci_checker) { checker }

    prepare.send(:ensure_green_ci!)

    assert_equal ["Checking CI status for HEAD..."], ui.infos
    assert_equal ["abc123"], calls
    assert_empty ui.warnings
  end

  def test_pr_comment_starts_with_llm_attribution
    context = Object.new
    context.define_singleton_method(:comment_attribution) do |model_name|
      "This comment was written by #{model_name} working on behalf of [puma-release](https://github.com/nateberkopec/puma-release)."
    end
    context.define_singleton_method(:comment_author_model_name) { "fallback-model" }
    prepare = PumaRelease::Commands::Prepare.allocate
    prepare.instance_variable_set(:@context, context)

    comment = prepare.send(
      :pr_comment,
      {
        "model_name" => "openai-codex/gpt-5.4",
        "bump_type" => "minor",
        "reasoning_markdown" => "Because of [this commit](https://github.com/puma/puma/commit/abc)."
      },
      nil
    )

    assert_match(%r{\AThis comment was written by openai-codex/gpt-5\.4 working on behalf of \[puma-release\]\(https://github.com/nateberkopec/puma-release\)\.}, comment)
  end

  def test_ensure_draft_release_uses_the_proposal_tag
    git_repo = Object.new
    git_repo.define_singleton_method(:proposal_tag) { |_version| "v7.3.0-proposal" }

    repo_files = Object.new
    repo_files.define_singleton_method(:release_name) { |_version| "v7.3.0 - Example" }
    repo_files.define_singleton_method(:extract_history_section) { |_version| "* Features\n  * Example ([#1])" }

    calls = []
    github = Object.new
    github.define_singleton_method(:release) { |_tag| nil }
    github.define_singleton_method(:create_release) do |tag, body, title:, draft:, target:|
      calls << [:create_release, tag, body, title, draft, target]
      {"name" => title, "body" => body, "targetCommitish" => target}
    end
    github.define_singleton_method(:edit_release_target) { |_tag, _target| flunk "edit_release_target should not be called when the draft release target already matches" }
    github.define_singleton_method(:edit_release_title) { |_tag, _title| flunk "edit_release_title should not be called when the title already matches" }
    github.define_singleton_method(:edit_release_notes) { |_tag, _body| flunk "edit_release_notes should not be called when the notes already match" }

    prepare = PumaRelease::Commands::Prepare.allocate
    prepare.instance_variable_set(:@context, OpenStruct.new(history_file: Pathname("History.md")))
    prepare.instance_variable_set(:@git_repo, git_repo)
    prepare.instance_variable_set(:@repo_files, repo_files)
    prepare.instance_variable_set(:@github, github)

    prepare.send(:ensure_draft_release, "7.3.0", "release-v7.3.0")

    assert_equal [[:create_release, "v7.3.0-proposal", "* Features\n  * Example ([#1])", "v7.3.0 - Example", true, "release-v7.3.0"]], calls
  end

  def test_call_checks_out_the_release_branch_before_updating_release_files
    sequence = []
    ui = FakeUI.new
    events = Object.new
    events.define_singleton_method(:publish) { |_name, _payload| }
    context = OpenStruct.new(
      ui:,
      events:,
      codename: nil,
      metadata_repo: "puma/puma",
      history_file: Pathname("History.md")
    )
    context.define_singleton_method(:check_dependencies!) { |_git, _gh, _agent| }
    context.define_singleton_method(:announce_live_mode!) {}
    context.define_singleton_method(:ensure_release_writes_allowed!) {}
    context.define_singleton_method(:agent_binary) { "pi" }

    git_repo = Object.new
    git_repo.define_singleton_method(:ensure_clean_base!) { sequence << :ensure_clean_base }
    git_repo.define_singleton_method(:last_tag) { "v7.2.0" }
    git_repo.define_singleton_method(:bump_version) { |_current, _bump| "7.2.1" }
    git_repo.define_singleton_method(:checkout_release_branch!) { |branch| sequence << [:checkout_release_branch, branch] }
    git_repo.define_singleton_method(:proposal_tag) { |_version| "v7.2.1-proposal" }
    git_repo.define_singleton_method(:commit_release!) { |_version, extra_files:| sequence << [:commit_release, extra_files] }
    git_repo.define_singleton_method(:push_branch!) { |_branch| sequence << :push_branch }
    git_repo.define_singleton_method(:head_sha) { "abc123" }

    repo_files = Object.new
    repo_files.define_singleton_method(:current_version) { "7.2.0" }
    repo_files.define_singleton_method(:prepend_history_section!) { |_version, _changelog, _refs| sequence << :prepend_history_section }
    repo_files.define_singleton_method(:update_version!) { |_version, _bump_type, codename:| sequence << [:update_version, codename] }
    repo_files.define_singleton_method(:release_name) { |_version| "v7.2.1" }
    repo_files.define_singleton_method(:extract_history_section) { |_version| "* Changes\n  * Example ([#1])" }

    github = Object.new
    github.define_singleton_method(:create_release_pr) do |_title, _branch, body:|
      sequence << [:create_release_pr, body]
      "https://example.test/pr"
    end
    github.define_singleton_method(:comment_on_pr) { |_url, _body| sequence << :comment_on_pr }
    github.define_singleton_method(:update_pr_body) { |_url, _body| sequence << :update_pr_body }
    github.define_singleton_method(:release) { |_tag| nil }
    github.define_singleton_method(:create_release) do |_tag, _body, title:, draft:, target:|
      sequence << [:create_release, title, draft, target]
      {"name" => title, "body" => "* Changes\n  * Example ([#1])", "targetCommitish" => target, "url" => "https://example.test/release"}
    end
    github.define_singleton_method(:edit_release_target) { |_tag, _target| flunk "edit_release_target should not be called when the target already matches" }
    github.define_singleton_method(:edit_release_title) { |_tag, _title| flunk "edit_release_title should not be called when the title already matches" }
    github.define_singleton_method(:edit_release_notes) { |_tag, _body| flunk "edit_release_notes should not be called when the notes already match" }

    contributors = Object.new
    contributors.define_singleton_method(:codename_earner) { |_tag| nil }

    prepare = PumaRelease::Commands::Prepare.allocate
    prepare.instance_variable_set(:@context, context)
    prepare.instance_variable_set(:@git_repo, git_repo)
    prepare.instance_variable_set(:@repo_files, repo_files)
    prepare.instance_variable_set(:@github, github)
    prepare.instance_variable_set(:@contributors, contributors)
    prepare.define_singleton_method(:ensure_green_ci!) { sequence << :ensure_green_ci }
    prepare.define_singleton_method(:recommend_version) { |_range| {"bump_type" => "patch", "reasoning_markdown" => "Patch release"} }
    prepare.define_singleton_method(:show_version_recommendation) { |_recommendation| sequence << :show_version_recommendation }
    prepare.define_singleton_method(:show_codename_earner) { |_tag, _bump_type| nil }
    prepare.define_singleton_method(:prepare_changelog) { |_range, _new_version, _last_tag| "* Changes\n  * Example ([#1])" }
    prepare.define_singleton_method(:build_link_references) { |_changelog| "[#1]: https://example.test/pr/1\n" }
    prepare.define_singleton_method(:write_upgrade_guide) { |_range, _new_version, _recommendation, _bump_type| nil }
    prepare.define_singleton_method(:update_security_policy) { |_new_version, _bump_type| nil }
    prepare.define_singleton_method(:pr_comment) { |_recommendation, _earner| "comment" }

    assert_equal :wait_for_merge, prepare.call

    checkout_index = sequence.index([:checkout_release_branch, "release-v7.2.1"])
    prepend_index = sequence.index(:prepend_history_section)
    update_version_index = sequence.index([:update_version, nil])

    refute_nil checkout_index
    refute_nil prepend_index
    refute_nil update_version_index
    assert_operator checkout_index, :<, prepend_index
    assert_operator checkout_index, :<, update_version_index
  end

  def test_resume_follow_up_uses_the_prepare_checkpoint_to_finish_release_setup
    Dir.mktmpdir do |dir|
      checkpoint_file = Pathname(dir).join("prepare.json")
      checkpoint_file.write(
        JSON.pretty_generate(
          {
            "branch" => "release-v7.3.0",
            "compare_url" => "https://example.test/compare",
            "pr_comment" => "checkpoint comment",
            "release_body" => "* Features\n  * Example ([#1])",
            "release_title" => "v7.3.0 - Example",
            "version" => "7.3.0"
          }
        )
      )

      ui = FakeUI.new
      context = OpenStruct.new(ui:, prepare_checkpoint_file: checkpoint_file)
      context.define_singleton_method(:check_dependencies!) { |_gh| }
      context.define_singleton_method(:announce_live_mode!) {}
      context.define_singleton_method(:ensure_release_writes_allowed!) {}

      git_repo = Object.new
      git_repo.define_singleton_method(:proposal_tag) { |_version| "v7.3.0-proposal" }

      calls = []
      github = Object.new
      github.define_singleton_method(:open_release_pr) { {"number" => 7, "url" => "https://example.test/pr/7", "headRefName" => "release-v7.3.0"} }
      github.define_singleton_method(:pr_comments) { |_number| [] }
      github.define_singleton_method(:comment_on_pr) { |url, body| calls << [:comment_on_pr, url, body] }
      github.define_singleton_method(:release) { |_tag| nil }
      github.define_singleton_method(:create_release) do |tag, body, title:, draft:, target:|
        calls << [:create_release, tag, body, title, draft, target]
        {"name" => title, "body" => body, "targetCommitish" => target, "url" => "https://example.test/release"}
      end
      github.define_singleton_method(:edit_release_target) { |_tag, _target| flunk "edit_release_target should not be called when the target already matches" }
      github.define_singleton_method(:edit_release_title) { |_tag, _title| flunk "edit_release_title should not be called when the title already matches" }
      github.define_singleton_method(:edit_release_notes) { |_tag, _body| flunk "edit_release_notes should not be called when the notes already match" }
      github.define_singleton_method(:update_pr_body) { |url, body| calls << [:update_pr_body, url, body] }

      prepare = PumaRelease::Commands::Prepare.allocate
      prepare.instance_variable_set(:@context, context)
      prepare.instance_variable_set(:@git_repo, git_repo)
      prepare.instance_variable_set(:@repo_files, Object.new)
      prepare.instance_variable_set(:@github, github)

      assert_equal :wait_for_merge, prepare.resume_follow_up
      assert_includes calls, [:comment_on_pr, "https://example.test/pr/7", "checkpoint comment"]
      assert_includes calls, [:create_release, "v7.3.0-proposal", "* Features\n  * Example ([#1])", "v7.3.0 - Example", true, "release-v7.3.0"]
      assert_includes calls, [:update_pr_body, "https://example.test/pr/7", "https://example.test/compare\n\nhttps://example.test/release"]
      refute checkpoint_file.exist?
      assert_includes ui.infos, "Resumed release PR follow-up: https://example.test/pr/7"
    end
  end

  def test_show_version_recommendation_prints_reasoning_and_breaking_changes
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    prepare = PumaRelease::Commands::Prepare.allocate
    prepare.instance_variable_set(:@context, context)

    output = capture_io do
      prepare.send(
        :show_version_recommendation,
        {
          "reasoning_markdown" => "Major because of [this commit](https://github.com/puma/puma/commit/abc123).",
          "breaking_changes" => ["Dropped support for an older Rack integration"]
        }
      )
    end.first

    assert_equal ["Version bump recommendation:"], ui.infos
    assert_equal ["Potential breaking changes:"], ui.warnings
    assert_includes output, "Major because of [this commit](https://github.com/puma/puma/commit/abc123)."
    assert_includes output, "- Dropped support for an older Rack integration"
  end
end
