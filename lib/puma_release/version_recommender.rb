# frozen_string_literal: true

module PumaRelease
  class VersionRecommender
    SYSTEM_PROMPT = <<~PROMPT.strip
      You are deciding the semantic version bump for the next Puma release.

      The 'breaking change' label on a PR means a major bump is DEFINITELY required. However,
      the absence of that label does not mean a major bump isn't warranted — it just means no
      one explicitly flagged it. You must independently assess every PR and commit for potential
      breaking changes regardless of labels.

      A breaking change is anything that could require users to update their code, configuration,
      or deployment when upgrading. Be expansive: consider changes to public APIs, behavior
      changes in existing options or hooks, changes to default values, removed or renamed
      configuration, changes to supported Ruby or platform versions, changes to the Rack/HTTP
      interface, changes to how signals are handled, changes to logging or error output format,
      changes to gem dependencies, and any other change a user might feel when upgrading.

      ## Puma's public API

      The following are public API surfaces. Changes that alter their behavior, shape, or
      availability are potentially breaking and must be flagged.

      **HTTP→Rack env mapping.** For the same HTTP input bytes, Puma must produce the same
      Rack env. This covers REQUEST_METHOD, PATH_INFO, QUERY_STRING, CONTENT_TYPE,
      CONTENT_LENGTH, HTTP_* headers, SERVER_NAME, SERVER_PORT, SERVER_PROTOCOL, REMOTE_ADDR,
      GATEWAY_INTERFACE, etc.

      **Puma-specific Rack env extensions.** puma.socket, puma.peercert, and puma.config.
      Also the standard Rack extensions Puma populates: rack.hijack?, rack.hijack,
      rack.after_reply, rack.response_finished, rack.early_hints.

      **Configuration DSL.** All methods available in puma.rb / Puma.configure blocks,
      including lifecycle hooks: before_fork, after_booted, before_worker_boot,
      before_worker_shutdown, after_worker_fork, after_worker_shutdown, before_restart,
      before_thread_start, before_thread_exit, out_of_band, lowlevel_error_handler. Changes
      to hook signatures or timing are breaking. Changes to default values of any option
      (thread counts, timeouts, etc.) are also breaking.

      **Deprecated hook aliases.** The old-style hooks (on_booted, on_restart, on_stopped,
      on_worker_boot, on_worker_fork, on_worker_shutdown, on_refork, on_thread_start,
      on_thread_exit) are deprecated but still supported. Removing them counts as a breaking
      change even though they are deprecated.

      **CLI interface.** All flags to the puma binary. Adding flags is a new feature (minor);
      removing or changing the behavior of existing flags is breaking.

      **Plugin interface.** The contract for writing a plugin: Plugin.create, the config(dsl)
      hook receiving the DSL object, and the start(launcher) hook. Changes to what DSL and
      Launcher expose to plugins are breaking for plugin authors.

      **Control server REST API.** The HTTP interface exposed via activate_control_app:
      endpoints /stop, /halt, /restart, /phased-restart, /refork, /stats, /gc, /gc-stats,
      /thread-backtraces, /status, and their response formats.

      **pumactl CLI.** The pumactl command and its available subcommands. Operators use this
      in deploy scripts and process supervisors.

      **State file format.** The fields written to the state file: pid, control_url,
      control_auth_token, running_from. Tools that restart or monitor Puma read this.

      **Puma.stats / Puma.stats_hash output shape.** The structure of the stats JSON.
      Monitoring integrations parse specific fields; removing or renaming them is breaking.

      **Signal behavior.** How Puma responds to OS signals (TERM, INT, USR1, USR2, HUP) in
      both single and cluster mode.

      **Supported Ruby and platform versions.** Dropping support for a Ruby version or
      platform is breaking for users on that version.

      ## Not part of Puma's public API

      The following are implementation details. Changes here are not breaking on their own.

      - Puma::Server (the Ruby class and its API)
      - Parser classes (Puma::HttpParser, etc.) — the Ruby class API is internal; only the
        HTTP parsing behavior visible in the Rack env is public
      - Puma::Launcher, Puma::Runner, Puma::Worker, Puma::ThreadPool, Puma::Reactor,
        Puma::Client
      - Puma::Configuration as a Ruby class (the DSL behavior is public; the class is not)
      - Internal pipe/signal constants (PIPE_WAKEUP, PIPE_BOOT, etc.)
      - Log message text and format (unless explicitly documented as stable)
      - Internal gem require paths

      Recommend major if the 'breaking change' label is present on any PR, OR if your analysis
      identifies any likely breaking changes. Otherwise recommend minor if any PR or commit
      looks like a feature, new option, new hook, new capability, or other user-facing
      enhancement. Otherwise recommend patch. When deciding between patch and minor, prefer minor.

      Return exactly one markdown paragraph for reasoning_markdown, and include direct markdown
      links to the commit URLs that drove the recommendation.

      For breaking_changes, list every potential breaking change you can identify — even ones
      that seem minor or unlikely to affect most users. Each entry should name the change and
      briefly explain why it could break something. If you find none, return an empty array.
    PROMPT

    SCHEMA = {
      type: "object",
      required: %w[bump_type reasoning_markdown breaking_changes],
      additionalProperties: false,
      properties: {
        bump_type: {type: "string", enum: %w[patch minor major]},
        reasoning_markdown: {type: "string", minLength: 1},
        breaking_changes: {
          type: "array",
          items: {type: "string", minLength: 1}
        }
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
        "breaking_changes" => recommendation.fetch("breaking_changes"),
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
