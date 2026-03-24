# frozen_string_literal: true

require_relative "../test_helper"

class AgentClientTest < Minitest::Test
  def test_pi_mode_parses_plain_json_output
    shell = Class.new do
      attr_reader :command

      def output(*command, **)
        @command = command
        '{"bump_type":"patch","reasoning_markdown":"Because of [this commit](https://github.com/puma/puma/commit/abc)."}'
      end

      def stream_output(*command, **)
        output(*command)
      end

      def split(command)
        [command]
      end
    end.new

    context = OpenStruct.new(agent_cmd: "/tmp/pi", shell:)
    result = PumaRelease::AgentClient.new(context).ask_for_json(
      "Choose a version bump",
      system_prompt: "Return JSON",
      schema: {
        type: "object",
        required: %w[bump_type reasoning_markdown],
        properties: {
          bump_type: { type: "string" },
          reasoning_markdown: { type: "string" }
        }
      }
    )

    assert_equal "patch", result.fetch("bump_type")
    assert_includes shell.command, "-p"
    assert_includes shell.command, "--no-tools"
  end
end
