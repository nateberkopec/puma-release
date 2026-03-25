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
      { "name" => title, "body" => body, "targetCommitish" => target }
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
end
