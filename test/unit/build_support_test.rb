# frozen_string_literal: true

require_relative "../test_helper"

class BuildSupportTest < Minitest::Test
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

  def test_build_jruby_gem_uses_mise_ruby_jruby_runtime
    shell = FakeShell.new(
      {
        ["mise", "latest", "ruby@jruby"] => FakeShell::Result.new(stdout: "jruby-10.0.4.0\n", stderr: "", success?: true, exitstatus: 0),
        ["mise", "install", "java@21"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["mise", "where", "java@21"] => "/mise/java/21\n",
        ["mise", "install", "ruby@jruby-10.0.4.0"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "check"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "exec", "rake", "java", "gem"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0)
      }
    )
    ui = FakeUI.new
    context = OpenStruct.new(shell:, ui:)

    assert PumaRelease::BuildSupport.new(context).build_jruby_gem("8.0.0")
    assert_includes shell.commands, ["mise", "latest", "ruby@jruby"]
    assert_includes shell.commands, ["mise", "install", "java@21"]
    assert_includes shell.commands, ["mise", "where", "java@21"]
    assert_includes shell.commands, ["mise", "install", "ruby@jruby-10.0.4.0"]
    assert_includes shell.commands, ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "check"]
    assert_includes shell.commands, ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "exec", "rake", "java", "gem"]
    assert_operator shell.commands.index(["mise", "install", "java@21"]), :<, shell.commands.index(["mise", "install", "ruby@jruby-10.0.4.0"])
    assert_operator shell.commands.index(["mise", "install", "ruby@jruby-10.0.4.0"]), :<, shell.commands.index(["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "check"])
    assert_includes ui.infos, "Ensuring java@21 is installed for JRuby..."
    assert_includes ui.infos, "Ensuring ruby@jruby-10.0.4.0 is installed with java@21..."
    assert_includes ui.infos, "Ensuring JRuby bundle is installed with mise, java@21, and ruby@jruby-10.0.4.0..."
    assert_includes ui.infos, "Building JRuby gem with mise, java@21, and ruby@jruby-10.0.4.0..."
    assert_includes ui.infos, "Built: pkg/puma-8.0.0-java.gem"
  end

  def test_build_jruby_gem_runs_bundle_install_when_mise_bundle_check_fails
    shell = FakeShell.new(
      {
        ["mise", "latest", "ruby@jruby"] => FakeShell::Result.new(stdout: "jruby-10.0.4.0\n", stderr: "", success?: true, exitstatus: 0),
        ["mise", "install", "java@21"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["mise", "where", "java@21"] => "/mise/java/21\n",
        ["mise", "install", "ruby@jruby-10.0.4.0"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "check"] => FakeShell::Result.new(stdout: "", stderr: "missing gems", success?: false, exitstatus: 1),
        ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "install"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "exec", "rake", "java", "gem"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0)
      }
    )
    ui = FakeUI.new
    context = OpenStruct.new(shell:, ui:)

    assert PumaRelease::BuildSupport.new(context).build_jruby_gem("8.0.0")
    assert_includes shell.commands, ["mise", "exec", "java@21", "ruby@jruby-10.0.4.0", "--", "bundle", "install"]
  end

  def test_build_jruby_gem_falls_back_to_local_jruby_when_mise_cannot_resolve_ruby_jruby
    shell = FakeShell.new(
      {
        ["mise", "latest", "ruby@jruby"] => FakeShell::Result.new(stdout: "", stderr: "nope", success?: false, exitstatus: 1),
        ["jruby", "-S", "bundle", "check"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0),
        ["jruby", "-S", "bundle", "exec", "rake", "java", "gem"] => FakeShell::Result.new(stdout: "", stderr: "", success?: true, exitstatus: 0)
      }
    )
    shell.define_singleton_method(:available?) { |command| command == "mise" || command == "jruby" }
    ui = FakeUI.new
    context = OpenStruct.new(shell:, ui:)

    assert PumaRelease::BuildSupport.new(context).build_jruby_gem("8.0.0")
    assert_includes ui.warnings, "mise could not determine a JRuby version via ruby@jruby."
    assert_includes shell.commands, ["jruby", "-S", "bundle", "check"]
    assert_includes shell.commands, ["jruby", "-S", "bundle", "exec", "rake", "java", "gem"]
  end
end
