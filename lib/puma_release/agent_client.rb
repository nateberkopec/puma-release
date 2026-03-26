# frozen_string_literal: true

require "json"

module PumaRelease
  class AgentClient
    attr_reader :context, :last_model_name

    def initialize(context)
      @context = context
    end

    def ask_for_json(prompt, system_prompt:, schema:)
      @last_model_name = nil
      payload = if pi?
        ask_pi_for_json(prompt, system_prompt:, schema:)
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

    def ask_pi_for_json(prompt, system_prompt:, schema:)
      payload = nil
      progress = {ticks: 0, shown: false}

      context.shell.stream_json_events(*pi_command(json_prompt(prompt, schema), system_prompt:, mode: "json")) do |event|
        case event["type"]
        when "message_update", "tool_execution_update"
          tick_structured_progress(progress)
        when "message_end"
          next unless event.dig("message", "role") == "assistant"

          @last_model_name ||= extract_model_name(event.fetch("message"))
          payload = extract_text_from_message(event.fetch("message"))
        end
      end

      payload || raise(Error, "#{context.agent_cmd} returned no JSON payload")
    ensure
      finish_structured_progress(progress)
    end

    def pi_command(prompt, system_prompt:, mode: nil)
      command = context.shell.split(context.agent_cmd) + [
        "-p",
        "--thinking", "xhigh",
        "--tools", "read,bash",
        "--no-extensions",
        "--extension", pi_guard_extension_path,
        "--no-skills",
        "--no-prompt-templates",
        "--no-themes",
        "--system-prompt", system_prompt
      ]
      command += ["--mode", mode] if mode
      command + [prompt]
    end

    def json_prompt(prompt, schema)
      <<~PROMPT
        #{prompt}

        Return only valid JSON matching this schema:
        #{JSON.pretty_generate(schema)}
      PROMPT
    end

    def pi_guard_extension_path
      File.expand_path("../../config/pi-agent-guard.ts", __dir__)
    end

    def extract_text_from_message(message)
      text_content = Array(message.fetch("content", [])).select { |content| content["type"] == "text" }
      final_answer = text_content.select { |content| text_signature_phase(content["textSignature"]) == "final_answer" }
      payload = if final_answer.empty?
        text_content.rfind { |content| !content["text"].to_s.strip.empty? }.to_h["text"]
      else
        final_answer.map { |content| content["text"] }.join
      end
      payload.to_s
    end

    def text_signature_phase(signature)
      return nil if signature.to_s.empty?

      JSON.parse(signature).fetch("phase", nil)
    rescue JSON::ParserError
      nil
    end

    def extract_model_name(payload)
      return context.comment_author_model_name unless payload

      model = payload["model"].to_s.strip
      provider = payload["provider"].to_s.strip
      return "#{provider}/#{model}" unless provider.empty? || model.empty?
      return model unless model.empty?

      context.comment_author_model_name
    end

    def tick_structured_progress(progress)
      progress[:ticks] += 1
      return unless progress[:ticks] == 1 || (progress[:ticks] % 25).zero?

      $stdout.print(".")
      $stdout.flush
      progress[:shown] = true
    end

    def finish_structured_progress(progress)
      return unless progress[:shown]

      $stdout.puts
    end

    def ask_claude_for_json(prompt, system_prompt:, schema:)
      payload = nil
      context.shell.stream_json_events(*claude_command(system_prompt:, schema:), stdin_data: prompt) do |event|
        @last_model_name ||= extract_model_name(event["message"] || event)
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
