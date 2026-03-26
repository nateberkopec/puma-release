# frozen_string_literal: true

module PumaRelease
  class UpgradeGuideWriter
    SYSTEM_PROMPT = <<~PROMPT.strip
      You are writing the upgrade guide for a new major version of Puma, a Ruby web server gem.

      Follow this structure exactly:

      # Welcome to Puma X.X: Codename.

      (2-3 sentences describing what this release brings and why users should be excited.)

      Here's what you should do:

      1. Review the Upgrade section below to look for breaking changes that could affect you.
      2. Upgrade to version X.0 in your Gemfile and deploy.
      3. Open up a new bug issue if you find any problems.
      4. Join us in building Puma! We welcome first-timers. See [CONTRIBUTING.md](./CONTRIBUTING.md).

      For a complete list of changes, see [History.md](./History.md).

      ## What's New

      (Describe the major user-facing features and improvements in this release. Group related
      items under sub-headers if there are multiple themes. For each significant feature,
      explain what it is, why it matters to the user, and how to use or configure it — include
      a code example if applicable. Link to relevant PRs and issues using Markdown links to
      https://github.com/puma/puma/pull/NUMBER or /issues/NUMBER. Omit pure internal
      refactors, CI changes, and test-only changes.)

      ## Upgrade

      Check the following list to see if you're depending on any of these behaviors:

      (A numbered list. Each item must be specific and actionable: name the exact DSL method,
      CLI flag, environment variable, Ruby constant, or behavior that changed, and explain
      exactly what the user needs to do. Cover every breaking change provided. Use inline code
      formatting for config keys, env vars, CLI flags, Ruby class/method names, etc.)

      Then, update your Gemfile:

      `gem 'puma', '< X+1'`

      Tone and style rules:
      - Friendly and direct, matching the voice of the existing Puma upgrade guides.
      - Do not include an image line.
      - Do not invent breaking changes beyond what is provided and supported by the commit list.
      - Do not include a "then update your Gemfile" line at the end of the What's New section.
      - The Upgrade section must cover every breaking change in the provided list.
    PROMPT

    attr_reader :context, :release_range, :new_version, :breaking_changes, :codename

    def initialize(context, release_range, new_version:, breaking_changes:, codename:)
      @context = context
      @release_range = release_range
      @new_version = new_version
      @breaking_changes = breaking_changes
      @codename = codename
    end

    def call
      context.ui.info("Asking #{context.agent_cmd} to write upgrade guide for #{new_version}...")
      content = agent.ask_for_text(prompt, system_prompt: SYSTEM_PROMPT)
      path = upgrade_guide_path
      File.write(path, content.strip + "\n")
      context.ui.info("Wrote upgrade guide: #{path}")
      path
    end

    private

    def upgrade_guide_path
      major_minor = new_version.split(".").first(2).join(".")
      File.join(context.repo_dir, "docs", "#{major_minor}-Upgrade.md")
    end

    def prompt
      version_label = codename ? "#{new_version} (\"#{codename}\")" : new_version
      next_major = new_version.split(".").first.to_i + 1

      breaking_section = if breaking_changes.any?
        "The following breaking changes have been identified for this release:\n\n" +
          breaking_changes.map { |c| "- #{c}" }.join("\n")
      else
        "No specific breaking changes were pre-identified by the version recommender, " \
          "but this is a major version bump. Review the commits carefully for anything " \
          "that could require user action when upgrading."
      end

      <<~PROMPT
        Write the upgrade guide for Puma #{version_label}.

        The next major version after this will be #{next_major}, so the Gemfile constraint
        at the end of the Upgrade section should read: `gem 'puma', '< #{next_major}'`

        #{breaking_section}

        #{release_range.to_prompt_context}
      PROMPT
    end

    def agent = @agent ||= AgentClient.new(context)
  end
end
