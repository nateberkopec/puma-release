# frozen_string_literal: true

require_relative "../test_helper"

class RunTest < Minitest::Test
  class FakeUI
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(message)
      infos << message
    end
  end

  def test_recovers_prepare_from_a_local_release_branch_without_an_open_pr
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :recover_prepare

    git_repo = Object.new
    checkouts = []
    git_repo.define_singleton_method(:release_branch_base) { "main" }
    git_repo.define_singleton_method(:checkout_branch!) { |branch| checkouts << branch }

    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:git_repo) { git_repo }
    run.define_singleton_method(:confirm_step) { |step| step == :prepare }
    run.define_singleton_method(:run_step) { |step| step }

    assert_equal :prepare, run.call
    assert_equal ["Found a local release branch with no open PR. Switching back to main and retrying prepare."], ui.infos
    assert_equal ["main"], checkouts
  end

  def test_reports_an_orphaned_release_branch_when_the_base_branch_is_unknown
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :orphaned_release_branch

    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:confirm_step) { flunk "confirm_step should not be called for an orphaned release branch" }

    assert_equal :orphaned_release_branch, run.call
    assert_equal ["Found a local release branch with no open PR, but puma-release does not know which base branch to return to. Switch back to your base branch and rerun with --base-branch if needed."], ui.infos
  end

  def test_resumes_prepare_follow_up_without_prompting
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :prepare_follow_up
    prepare = Object.new
    prepare.define_singleton_method(:resume_follow_up) { :wait_for_merge }

    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:prepare_command) { prepare }
    run.define_singleton_method(:confirm_step) { flunk "confirm_step should not be called when resuming prepare follow-up" }

    assert_equal :wait_for_merge, run.call
  end

  def test_waits_for_rubygems_without_prompting
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :wait_for_rubygems
    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:confirm_step) { flunk "confirm_step should not be called while waiting for RubyGems" }

    assert_equal :wait_for_rubygems, run.call
    assert_equal ["Release artifacts are built, but RubyGems does not show both variants yet. Push both gems to RubyGems, wait for them to appear, and rerun puma-release."], ui.infos
  end

  def test_wait_for_merge_reports_the_open_pr_without_prompting_by_default
    ui = FakeUI.new
    context = OpenStruct.new(ui:, base_branch: "main")
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :wait_for_merge
    github = Object.new
    github.define_singleton_method(:open_release_pr) { {"url" => "https://example.test/pr/7"} }

    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:github) { github }
    run.define_singleton_method(:interactive_release_pr_merge?) { |_pr| false }

    assert_equal :wait_for_merge, run.call
    assert_equal ["A release PR is already in flight (https://example.test/pr/7). Merge it, update local main, and rerun puma-release."], ui.infos
  end

  def test_wait_for_merge_can_merge_interactively_and_continue
    ui = FakeUI.new
    context = OpenStruct.new(ui:, base_branch: "main")
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    steps = [:wait_for_merge, :build]
    detector.define_singleton_method(:next_step) { steps.shift }

    pr = {"url" => "https://example.test/pr/7"}
    merged = []
    github = Object.new
    github.define_singleton_method(:open_release_pr) { pr }
    github.define_singleton_method(:merge_pr) { |url| merged << url }

    updated = []
    git_repo = Object.new
    git_repo.define_singleton_method(:update_local_branch!) { |branch| updated << branch }

    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:github) { github }
    run.define_singleton_method(:git_repo) { git_repo }
    run.define_singleton_method(:interactive_release_pr_merge?) { |candidate| candidate == pr }
    run.define_singleton_method(:confirm_step) { |step| step == :build }
    run.define_singleton_method(:run_step) { |step| step }

    assert_equal :build, run.call
    assert_equal ["https://example.test/pr/7"], merged
    assert_equal ["main"], updated
    assert_equal [
      "Merging release PR: https://example.test/pr/7",
      "Merged release PR and updated local main. Continuing with the release."
    ], ui.infos
  end

  def test_returns_complete_without_prompt_when_release_is_already_complete
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :complete
    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:confirm_step) { flunk "confirm_step should not be called for a complete release" }

    assert_equal :complete, run.call
    assert_equal ["The current release is already complete. No action needed."], ui.infos
  end
end
