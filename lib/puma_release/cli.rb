# frozen_string_literal: true

module PumaRelease
  class CLI
    COMMANDS = {
      "prepare" => Commands::Prepare,
      "build" => Commands::Build,
      "github" => Commands::Github,
      "run" => Commands::Run
    }.freeze

    attr_reader :argv, :env

    def initialize(argv, env: ENV)
      @argv = argv
      @env = env
    end

    def run
      options = Options.parse(argv)
      context = Context.new(options, env:)
      subscribe(context)
      command = COMMANDS.fetch(options.fetch(:command)) { raise Error, usage }
      command.new(context).call
    rescue Error => e
      UI.new.error(e.message)
      exit 1
    end

    private

    def subscribe(context)
      context.events.subscribe(:checkpoint) do |_name, payload|
        next unless payload[:kind] == :wait_for_merge

        context.ui.info("Checkpoint: waiting for PR merge (#{payload[:pr_url]})")
      end
    end

    def usage
      [
        "Usage: puma-release [options] [command]",
        "",
        "Commands:",
        "  prepare   open the release PR and draft release",
        "  build     tag the release and build both gem artifacts",
        "  github    publish the GitHub release and upload assets",
        "  run       detect the next step and run it (default)"
      ].join("\n")
    end
  end
end
