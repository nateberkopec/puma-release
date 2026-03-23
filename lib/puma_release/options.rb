# frozen_string_literal: true

require "optparse"
require "pathname"

module PumaRelease
  class Options
    DEFAULTS = {
      command: "run",
      repo_dir: Dir.pwd,
      metadata_repo: "puma/puma",
      changelog_backend: "auto",
      allow_unknown_ci: false,
      yes: false
    }.freeze

    def self.parse(argv)
      options = DEFAULTS.dup
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: puma-release [options] [command]"

        opts.on("--repo-dir PATH", "Path to the Puma checkout") { |value| options[:repo_dir] = value }
        opts.on("--release-repo OWNER/REPO", "Repo for PRs, tags, and releases") { |value| options[:release_repo] = value }
        opts.on("--metadata-repo OWNER/REPO", "Repo for PR metadata and commit links") { |value| options[:metadata_repo] = value }
        opts.on("--allow-unknown-ci", "Proceed when CI status cannot be determined") { options[:allow_unknown_ci] = true }
        opts.on("--changelog-backend NAME", "auto, agent, or communique") { |value| options[:changelog_backend] = value }
        opts.on("-y", "--yes", "Skip interactive confirmations") { options[:yes] = true }
      end

      remaining = parser.parse(argv)
      options[:command] = remaining.first if remaining.first
      options[:repo_dir] = Pathname(options[:repo_dir]).expand_path
      options
    rescue OptionParser::ParseError => e
      raise Error, e.message
    end
  end
end
