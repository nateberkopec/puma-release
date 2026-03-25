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
    def commits_since(tag) = shell.output("git", "rev-list", "--count", "#{tag}..HEAD").strip.to_i

    def ensure_clean_main!
      raise Error, "Must be on 'main' branch (currently on '#{current_branch}')" unless current_branch == "main"
      raise Error, "Working directory not clean. Commit or stash first." unless clean?

      run_git!("fetch", metadata_remote, "--quiet")
      remote_sha = shell.output("git", "rev-parse", "#{metadata_remote}/main").strip
      raise Error, "Local main differs from #{metadata_remote}/main. Pull or push first." unless head_sha == remote_sha
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

    def top_contributors_since_with_email(tag)
      shell.output("git", "shortlog", "-s", "-n", "-e", "--no-merges", "#{tag}..HEAD").lines(chomp: true)
    end

    def commit_authors_since(tag)
      shell.output("git", "log", "--format=%H%x09%aN%x09%aE", "#{tag}..HEAD").lines(chomp: true).map do |line|
        sha, name, email = line.split("\t", 3)
        { sha:, name:, email: }
      end
    end

    def release_tag(version) = "v#{version}"

    def checkout_release_branch!(branch)
      run_git!("checkout", "-b", branch)
    end

    def commit_release!(version)
      run_git!("add", context.version_file.to_s, context.history_file.to_s)
      run_git!("commit", "-S", "-m", "Release v#{version}")
    end

    def push_branch!(branch)
      command = ["push"]
      command << "-u" if release_remote
      command += [release_push_target, branch]
      run_git!(*command)
    end

    def remote_tag_sha(tag, repo: context.release_repo)
      refs = shell.output("git", "ls-remote", "--tags", remote_target_for(repo), "refs/tags/#{tag}", "refs/tags/#{tag}^{}").lines(chomp: true)
      peeled = refs.find { |line| line.end_with?("refs/tags/#{tag}^{}") }
      direct = refs.find { |line| line.end_with?("refs/tags/#{tag}") }
      (peeled || direct).to_s.split.first.to_s
    end

    def remote_tag_object_sha(tag, repo: context.release_repo)
      shell.output("git", "ls-remote", "--tags", remote_target_for(repo), "refs/tags/#{tag}").split.first.to_s
    end

    def local_tag_sha(tag)
      shell.optional_output("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}^{commit}")
    end

    def local_tag_object_sha(tag)
      shell.optional_output("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}")
    end

    def create_signed_tag!(tag, message: "Release #{tag}")
      run_git!("tag", "-s", tag, "-m", message)
    end

    def local_tag_signed?(tag)
      return false if local_tag_sha(tag).empty?

      shell.output("git", "cat-file", "-p", "refs/tags/#{tag}").include?("-----BEGIN PGP SIGNATURE-----")
    end

    def ensure_release_tag_pushed!(tag)
      head = head_sha
      local = local_tag_sha(tag)
      remote = remote_tag_sha(tag)

      raise Error, "Remote tag #{tag} already exists at #{remote}, not HEAD #{head}." if !remote.empty? && remote != head
      raise Error, "Local tag #{tag} already exists at #{local}, not HEAD #{head}." if !local.empty? && local != head
      raise Error, "Local tag #{tag} exists at #{head} but is not GPG-signed." if !local.empty? && !local_tag_signed?(tag)

      create_signed_tag!(tag) if local.empty?

      local_object = local_tag_object_sha(tag)
      remote_object = remote_tag_object_sha(tag)
      return if !remote_object.empty? && remote_object == local_object

      raise Error, "Remote tag #{tag} already exists but does not match the local signed tag." unless remote_object.empty?

      run_git!("push", release_push_target, tag)
    end

    def delete_local_tag!(tag, allow_failure: false)
      run_git!("tag", "-d", tag, allow_failure:)
    end

    private

    def shell = context.shell

    def run_git!(*command, **options)
      context.confirm_live_git_command!("git", *command) if context.respond_to?(:confirm_live_git_command!)
      shell.run("git", *command, **options)
    end

    def metadata_remote
      remote_name_for(context.metadata_repo) || "origin"
    end

    def release_remote
      remote_name_for(context.release_repo)
    end

    def release_push_target
      release_remote || github_url_for(context.release_repo)
    end

    def remote_target_for(repo)
      remote_name_for(repo) || github_url_for(repo)
    end

    def remote_name_for(repo)
      shell.output("git", "remote").lines(chomp: true).find do |remote|
        github_repo_from_url(shell.output("git", "remote", "get-url", remote).strip) == repo
      end
    end

    def github_url_for(repo)
      origin_url = shell.output("git", "remote", "get-url", "origin").strip
      return "git@github.com:#{repo}.git" if origin_url.match?(%r{\A(?:git@github\.com:|ssh://git@github\.com/)})

      "https://github.com/#{repo}.git"
    end

    def github_repo_from_url(url)
      url[%r{github\.com[:/]([^/]+/[^/.]+?)(?:\.git)?$}, 1]
    end
  end
end
