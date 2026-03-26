# frozen_string_literal: true

module PumaRelease
  class ChangelogGenerator
    SYSTEM_PROMPT = <<~PROMPT.strip
      Draft a Puma release changelog as structured data.
      Use only these categories: Features, Bugfixes, Performance, Refactor, Docs, CI,
      Breaking changes.
      Rules:
      - Only include categories that have entries.
      - Every entry must have at least one PR number.
      - Keep descriptions concise and user-facing.
      - Omit purely internal noise unless it represents meaningful test infrastructure work.
      - Prefer combining closely related PRs into one entry when appropriate.
    PROMPT

    SCHEMA = {
      type: "object",
      required: ["entries"],
      additionalProperties: false,
      properties: {
        entries: {
          type: "array",
          minItems: 1,
          items: {
            type: "object",
            required: %w[category description pr_numbers],
            additionalProperties: false,
            properties: {
              category: {
                type: "string",
                enum: ["Features", "Bugfixes", "Performance", "Refactor", "Docs", "CI", "Breaking changes"]
              },
              description: { type: "string", minLength: 1 },
              pr_numbers: {
                type: "array",
                minItems: 1,
                items: { type: "integer", minimum: 1 }
              }
            }
          }
        }
      }
    }.freeze

    attr_reader :context, :release_range, :new_tag, :last_tag

    def initialize(context, release_range, new_tag:, last_tag:)
      @context = context
      @release_range = release_range
      @new_tag = new_tag
      @last_tag = last_tag
    end

    def call
      5.times do |index|
        context.ui.info("Generating changelog (attempt #{index + 1}/5)...")
        changelog = backend.call.strip
        errors = validator.validate(changelog)
        return changelog if errors.empty?

        context.ui.warn("Generated changelog did not match the required format:")
        errors.each { |message| context.ui.warn(message) }
      end
      raise Error, "Could not generate a valid changelog after 5 attempts."
    end

    private

    def backend
      preferred = context.changelog_backend
      return CommuniqueBackend.new(context, new_tag, last_tag) if preferred == "communique"
      return AgentBackend.new(context, release_range, new_tag, last_tag) if preferred == "agent"
      return CommuniqueBackend.new(context, new_tag, last_tag) if communique_available?

      AgentBackend.new(context, release_range, new_tag, last_tag)
    end

    def communique_available?
      context.shell.available?("communique") && !context.env.fetch("ANTHROPIC_API_KEY", "").empty?
    end

    def validator = @validator ||= ChangelogValidator.new

    class AgentBackend
      def initialize(context, release_range, new_tag, last_tag)
        @context = context
        @release_range = release_range
        @new_tag = new_tag
        @last_tag = last_tag
      end

      def call
        context.ui.info("Asking #{context.agent_cmd} to draft changelog entries...")
        payload = agent.ask_for_json(prompt, system_prompt: SYSTEM_PROMPT, schema: SCHEMA)
        context.ui.info("Rendering changelog...")
        render(payload.fetch("entries"))
      end

      private

      CATEGORY_ORDER = ["Features", "Bugfixes", "Performance", "Refactor", "Docs", "CI", "Breaking changes"].freeze

      attr_reader :context, :release_range, :new_tag, :last_tag

      def prompt
        <<~PROMPT
          Draft the changelog entries for #{new_tag} from #{last_tag}..HEAD.

          Return JSON only.
          Each entry must include:
          - category: one of the allowed categories
          - description: concise release-note text with no PR refs in the text
          - pr_numbers: an array of GitHub PR numbers supporting the entry

          #{release_range.to_prompt_context}
        PROMPT
      end

      def render(entries)
        grouped = entries.group_by { |entry| entry.fetch("category") }
        CATEGORY_ORDER.filter_map do |category|
          next if grouped[category].to_a.empty?

          (["* #{category}"] + grouped.fetch(category).map { |entry| render_entry(entry) }).join("\n")
        end.join("\n\n")
      end

      def render_entry(entry)
        pr_refs = entry.fetch("pr_numbers").uniq.map { |number| "[#" + number.to_s + "]" }
        description = entry.fetch("description").strip.gsub(/\s+/, " ").sub(/[.。]\z/, "")
        "  * #{description} (#{pr_refs.join(', ')})"
      end

      def agent = @agent ||= AgentClient.new(context)
    end

    class CommuniqueBackend
      CONFIG = File.expand_path("../../config/communique.toml", __dir__)

      def initialize(context, new_tag, last_tag)
        @context = context
        @new_tag = new_tag
        @last_tag = last_tag
      end

      def call
        result = context.shell.run(
          "communique", "generate", new_tag, last_tag,
          "--concise", "--dry-run", "--config", CONFIG,
          env_overrides: github_env,
          allow_failure: true
        )
        raise Error, "communique failed. Is ANTHROPIC_API_KEY set?" unless result.success?

        result.stdout
      end

      private

      attr_reader :context, :new_tag, :last_tag

      def github_env
        token = context.github_token
        token.empty? ? {} : { "GITHUB_TOKEN" => token }
      end
    end
  end
end
