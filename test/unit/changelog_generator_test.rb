# frozen_string_literal: true

require_relative "../test_helper"

class ChangelogGeneratorTest < Minitest::Test
  class SilentUI
    def info(_message)
    end

    def warn(_message)
    end
  end

  def test_retries_with_validator_feedback
    attempts = []
    backend = Object.new
    backend.define_singleton_method(:call) do |validation_feedback:|
      attempts << validation_feedback
      (attempts.length == 1) ? "invalid" : "* Features\n  * Add a thing ([#1])"
    end

    validator = Object.new
    validator.define_singleton_method(:validate) do |changelog|
      (changelog == "invalid") ? ["Line 1: unsupported category."] : []
    end

    context = OpenStruct.new(ui: SilentUI.new)
    generator = PumaRelease::ChangelogGenerator.new(context, nil, new_tag: "v8.0.0", last_tag: "v7.2.0")
    generator.define_singleton_method(:backend) { backend }
    generator.define_singleton_method(:validator) { validator }

    changelog = generator.call

    assert_equal "* Features\n  * Add a thing ([#1])", changelog
    assert_nil attempts.first
    assert_includes attempts.last, "Previous attempt did not match the required format:"
    assert_includes attempts.last, "- Line 1: unsupported category."
  end

  def test_agent_backend_appends_validator_feedback_to_the_prompt
    captured_prompt = nil
    agent = Object.new
    agent.define_singleton_method(:ask_for_json) do |prompt, system_prompt:, schema:|
      captured_prompt = prompt
      {
        "entries" => [
          {"category" => "Features", "description" => "Add a thing", "pr_numbers" => [1]}
        ]
      }
    end

    release_range = Object.new
    release_range.define_singleton_method(:to_prompt_context) { "Repository: puma/puma" }

    context = OpenStruct.new(ui: SilentUI.new, agent_cmd: "pi")
    backend = PumaRelease::ChangelogGenerator::AgentBackend.new(context, release_range, "v8.0.0", "v7.2.0")
    backend.define_singleton_method(:agent) { agent }

    changelog = backend.call(validation_feedback: "Previous attempt did not match the required format:\n- Line 1: unsupported category.")

    assert_equal "* Features\n  * Add a thing ([#1])", changelog
    assert_includes captured_prompt, "Previous attempt did not match the required format:"
    assert_includes captured_prompt, "- Line 1: unsupported category."
    assert_includes captured_prompt, "Repository: puma/puma"
  end

  def test_communique_backend_injects_validator_feedback_into_a_temp_config
    shell = Class.new do
      attr_reader :command, :config_contents, :env_overrides

      def run(*command, env_overrides:, allow_failure:)
        @command = command
        @env_overrides = env_overrides
        @config_contents = File.read(command[command.index("--config") + 1])
        FakeShell::Result.new(stdout: "* Features\n  * Add a thing ([#1])\n", stderr: "", success?: true, exitstatus: 0)
      end
    end.new

    context = OpenStruct.new(shell:, github_token: "token")
    backend = PumaRelease::ChangelogGenerator::CommuniqueBackend.new(context, "v8.0.0", "v7.2.0")

    changelog = backend.call(validation_feedback: "Previous attempt did not match the required format:\n- Line 1: unsupported category.")

    assert_equal "* Features\n  * Add a thing ([#1])\n", changelog
    assert_equal({"GITHUB_TOKEN" => "token"}, shell.env_overrides)
    assert_includes shell.command, "communique"
    assert_includes shell.command, "--config"
    assert_includes shell.config_contents, "output the changelog using this exact format"
    assert_includes shell.config_contents, "Previous attempt did not match the required format:"
    assert_includes shell.config_contents, "- Line 1: unsupported category."
  end
end
