# frozen_string_literal: true

module PumaRelease
  class VersionRecommender
    SYSTEM_PROMPT = <<~PROMPT.strip
      You are deciding the semantic version bump for the next Puma release.
      Recommend major if any relevant PR in the release range has the 'breaking change' label.
      Otherwise recommend minor if any PR or commit looks like a feature, new option, new hook,
      new capability, or other user-facing enhancement. Otherwise recommend patch.
      When deciding between patch and minor, prefer minor.
      Return exactly one markdown paragraph for reasoning_markdown, and include direct markdown
      links to the commit URLs that drove the recommendation.
    PROMPT

    SCHEMA = {
      type: "object",
      required: %w[bump_type reasoning_markdown],
      additionalProperties: false,
      properties: {
        bump_type: { type: "string", enum: %w[patch minor major] },
        reasoning_markdown: { type: "string", minLength: 1 }
      }
    }.freeze

    attr_reader :context, :release_range

    def initialize(context, release_range)
      @context = context
      @release_range = release_range
    end

    def call
      context.ui.info("Asking #{context.agent_cmd} to recommend the version bump...")
      recommendation = agent.ask_for_json(prompt, system_prompt: SYSTEM_PROMPT, schema: SCHEMA)
      bump_type = recommendation.fetch("bump_type")
      reasoning = recommendation.fetch("reasoning_markdown").strip
      raise Error, "#{context.agent_cmd} returned an invalid bump type" unless %w[patch minor major].include?(bump_type)
      raise Error, "#{context.agent_cmd} returned empty bump reasoning" if reasoning.empty?
      raise Error, "#{context.agent_cmd} must include commit links in its reasoning" unless reasoning.include?("https://github.com/#{context.metadata_repo}/commit/")
      raise Error, "#{context.agent_cmd} must return bump reasoning as a single paragraph" if reasoning.include?("\n\n")

      {
        "bump_type" => bump_type,
        "reasoning_markdown" => reasoning,
        "model_name" => agent.last_model_name || context.comment_author_model_name
      }
    end

    private

    def prompt
      <<~PROMPT
        Determine the semantic version bump for the next Puma release.
        Return JSON that matches the provided schema.

        #{release_range.to_prompt_context}
      PROMPT
    end

    def agent = @agent ||= AgentClient.new(context)
  end
end
