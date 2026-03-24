# frozen_string_literal: true

require "json"

module PumaRelease
  class AgentClient
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def ask_for_json(prompt, system_prompt:, schema:)
      payload = if pi?
        JSON.parse(context.shell.stream_output(*pi_command(json_prompt(prompt, schema), system_prompt:)).strip)
      else
        ask_claude_for_json(prompt, system_prompt:, schema:)
      end
      payload = JSON.parse(payload) if payload.is_a?(String)
      payload
    rescue JSON::ParserError => e
      raise Error, "#{context.agent_cmd} returned invalid JSON: #{e.message}"
    end

    def ask_for_text(prompt, system_prompt:)
      return context.shell.stream_output(*pi_command(prompt, system_prompt:)).strip if pi?

      context.shell.stream_output(*claude_command(system_prompt:), stdin_data: prompt).strip
    end

    private

    def pi?
      File.basename(context.shell.split(context.agent_cmd).first.to_s) == "pi"
    end

    def pi_command(prompt, system_prompt:)
      context.shell.split(context.agent_cmd) + [
        "-p",
        "--no-session",
        "--no-tools",
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "--no-themes",
        "--system-prompt", system_prompt,
        prompt
      ]
    end

    def json_prompt(prompt, schema)
      <<~PROMPT
        #{prompt}

        Return only valid JSON matching this schema:
        #{JSON.pretty_generate(schema)}
      PROMPT
    end

    def ask_claude_for_json(prompt, system_prompt:, schema:)
      payload = nil
      context.shell.stream_json_events(*claude_command(system_prompt:, schema:), stdin_data: prompt) do |event|
        case event["type"]
        when "assistant"
          Array(event.dig("message", "content")).each do |content|
            next unless content["type"] == "text"
            $stdout.print(content["text"])
            $stdout.flush
          end
        when "result"
          payload = event["structured_output"] || JSON.parse(event.fetch("result"))
        end
      end
      payload
    end

    def claude_command(system_prompt:, schema: nil)
      command = context.shell.split(context.agent_cmd) + [
        "-p",
        "--allowedTools", "",
        "--permission-mode", "bypassPermissions",
        "--system-prompt", system_prompt
      ]
      return command unless schema

      command + ["--output-format", "stream-json", "--json-schema", JSON.generate(schema)]
    end
  end
end
