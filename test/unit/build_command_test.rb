# frozen_string_literal: true

require_relative "../test_helper"

class BuildCommandTest < Minitest::Test
  class FakeUI
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(message)
      infos << message
    end

    def warn(_message)
    end
  end

  def test_checks_git_and_bundle_before_building
    calls = []
    context = Object.new
    context.define_singleton_method(:check_dependencies!) { |*commands| calls << commands }
    context.define_singleton_method(:announce_live_mode!) {}
    context.define_singleton_method(:ensure_release_writes_allowed!) {}

    git_repo = Object.new
    git_repo.define_singleton_method(:ensure_clean_base!) { calls << :clean_base }

    repo_files = Object.new
    repo_files.define_singleton_method(:current_version) { raise PumaRelease::Error, "stop" }

    command = PumaRelease::Commands::Build.allocate
    command.instance_variable_set(:@context, context)
    command.instance_variable_set(:@git_repo, git_repo)
    command.instance_variable_set(:@repo_files, repo_files)

    error = assert_raises(PumaRelease::Error) { command.call }

    assert_equal "stop", error.message
    assert_includes calls, ["git", "bundle"]
    assert_includes calls, :clean_base
  end

  def test_prints_exact_fnox_gem_push_commands_after_building
    context = Object.new
    ui = FakeUI.new
    shell = FakeShell.new
    shell.define_singleton_method(:available?) { |_command| false }
    events = Object.new
    published_events = []
    events.define_singleton_method(:publish) { |*args| published_events << args }
    context.define_singleton_method(:check_dependencies!) { |*_commands| }
    context.define_singleton_method(:announce_live_mode!) {}
    context.define_singleton_method(:ensure_release_writes_allowed!) {}
    context.define_singleton_method(:shell) { shell }
    context.define_singleton_method(:ui) { ui }
    context.define_singleton_method(:events) { events }
    context.define_singleton_method(:repo_dir) { Pathname("/tmp/puma checkout") }

    git_repo = Object.new
    git_repo.define_singleton_method(:ensure_clean_base!) {}
    git_repo.define_singleton_method(:release_tag) { |version| "v#{version}" }
    git_repo.define_singleton_method(:ensure_release_tag_pushed!) { |_tag| }

    repo_files = Object.new
    repo_files.define_singleton_method(:current_version) { "8.0.1" }

    command = PumaRelease::Commands::Build.allocate
    command.instance_variable_set(:@context, context)
    command.instance_variable_set(:@git_repo, git_repo)
    command.instance_variable_set(:@repo_files, repo_files)

    stdout, = capture_io do
      assert_equal :wait_for_rubygems, command.call
    end

    assert_includes ui.infos, "STOP: push both gems to RubyGems, then rerun puma-release."
    assert_includes stdout, "Run these exact commands:\n"
    assert_includes stdout, "  fnox exec -- gem push --otp <INSERT_OTP_HERE> /tmp/puma\\ checkout/pkg/puma-8.0.1.gem\n"
    assert_includes stdout, "  fnox exec -- gem push --otp <INSERT_OTP_HERE> /tmp/puma\\ checkout/pkg/puma-8.0.1-java.gem\n"
    assert_equal [[:checkpoint, {kind: :wait_for_rubygems, version: "8.0.1", tag: "v8.0.1"}]], published_events
  end
end
