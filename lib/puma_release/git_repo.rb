# frozen_string_literal: true

module PumaRelease
  class GitRepo
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def current_branch = shell.output("git", "rev-parse", "--abbrev-ref", "HEAD").strip
    def clean? = shell.output("git", "status", "--porcelain").strip.empty?
    def head_sha = shell.output("git", "rev-parse", "HEAD").strip

    def ensure_clean_main!
      raise Error, "Must be on 'main' branch (currently on '#{current_branch}')" unless current_branch == "main"
      raise Error, "Working directory not clean. Commit or stash first." unless clean?

      shell.run("git", "fetch", "origin", "--quiet")
      remote_sha = shell.output("git", "rev-parse", "origin/main").strip
      raise Error, "Local main differs from origin/main. Pull or push first." unless head_sha == remote_sha
    end

    def last_tag
      tags = shell.output("git", "tag", "--sort=-v:refname").lines(chomp: true)
      tags.find { |tag| tag.match?(/^v\d/) } || raise(Error, "Could not determine last release tag")
    end

    def bump_version(version, bump_type)
      major, minor, patch = version.split(".").map(&:to_i)
      return "#{major + 1}.0.0" if bump_type == "major"
      return "#{major}.#{minor + 1}.0" if bump_type == "minor"
      return "#{major}.#{minor}.#{patch + 1}" if bump_type == "patch"

      raise Error, "Unknown bump type: #{bump_type}"
    end

    def top_contributors_since(tag)
      shell.output("git", "shortlog", "-s", "-n", "--no-merges", "#{tag}..HEAD").lines(chomp: true)
    end

    def codename_earner(tag)
      top_contributors_since(tag).first.to_s.sub(/^\s*\d+\s*/, "")
    end

    def release_tag(version) = "v#{version}"

    def checkout_release_branch!(branch)
      shell.run("git", "checkout", "-b", branch)
    end

    def commit_release!(version)
      shell.run("git", "add", context.version_file.to_s, context.history_file.to_s)
      shell.run("git", "commit", "--no-gpg-sign", "-m", "Release v#{version}")
    end

    def push_branch!(branch)
      shell.run("git", "push", "-u", "origin", branch)
    end

    def ensure_release_tag_pushed!(tag)
      head = head_sha
      local = shell.optional_output("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}^{commit}")
      remote = shell.output("git", "ls-remote", "--refs", "--tags", "origin", "refs/tags/#{tag}").split.first.to_s

      raise Error, "Remote tag #{tag} already exists at #{remote}, not HEAD #{head}." if !remote.empty? && remote != head
      return if remote == head
      raise Error, "Local tag #{tag} already exists at #{local}, not HEAD #{head}." if !local.empty? && local != head

      shell.run("git", "tag", "--no-sign", tag) if local.empty?
      shell.run("git", "push", "origin", tag)
    end

    private

    def shell = context.shell
  end
end
