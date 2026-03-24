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
end
