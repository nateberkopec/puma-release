# frozen_string_literal: true

require_relative "../test_helper"

class BuildSupportTest < Minitest::Test
  def test_uses_override_command_when_present
    shell = FakeShell.new
    ui = Object.new
    def ui.info(*) = nil
    context = OpenStruct.new(env: { "PUMA_RELEASE_JRUBY_BUILD_COMMAND" => "bundle exec rake java gem" }, shell:, ui:)

    assert PumaRelease::BuildSupport.new(context).build_jruby_gem("7.2.1")
    assert_includes shell.commands, ["bundle", "exec", "rake", "java", "gem"]
  end
end
