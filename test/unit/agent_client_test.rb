# frozen_string_literal: true

require "stringio"
require_relative "../test_helper"

class AgentClientTest < Minitest::Test
  def test_pi_mode_parses_json_from_event_stream_without_printing_json_payload
    shell = Class.new do
      attr_reader :command

      def stream_json_events(*command, **)
        @command = command
        yield({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => "{" } })
        yield({
                "type" => "message_end",
                "message" => {
                  "role" => "assistant",
                  "provider" => "openai-codex",
                  "model" => "gpt-5.4",
                  "content" => [
                    { "type" => "text", "text" => '{"bump_type":"patch","reasoning_markdown":"Because of [this commit](https://github.com/puma/puma/commit/abc)."}' }
                  ]
                }
              })
      end

      def split(command)
        [command]
      end
    end.new

    context = OpenStruct.new(agent_cmd: "/tmp/pi", shell:)
    original_stdout = $stdout
    $stdout = StringIO.new

    client = PumaRelease::AgentClient.new(context)
    result = client.ask_for_json(
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
    assert_includes shell.command, "--mode"
    assert_equal "openai-codex/gpt-5.4", client.last_model_name
    assert_equal ".\n", $stdout.string
  ensure
    $stdout = original_stdout
  end
end
