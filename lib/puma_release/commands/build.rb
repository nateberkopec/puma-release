# frozen_string_literal: true

module PumaRelease
  module Commands
    class Build
      attr_reader :context, :git_repo, :repo_files, :github

      def initialize(context)
        @context = context
        @git_repo = GitRepo.new(context)
        @repo_files = RepoFiles.new(context)
        @github = GitHubClient.new(context)
      end

      def call
        context.check_dependencies!("git", "gh", "bundle")
        context.announce_live_mode!
        context.ensure_release_writes_allowed!
        git_repo.ensure_clean_main!
        version = repo_files.current_version
        tag = git_repo.release_tag(version)
        context.ui.info("Ensuring tag #{tag} points at HEAD and is pushed...")
        retarget_draft_release_tag_if_needed(tag)
        git_repo.ensure_release_tag_pushed!(tag)
        sync_release_target_to_head(tag)
        sync_release_title(tag, version)
        context.ui.info("Building MRI gem...")
        context.shell.run("bundle", "exec", "rake", "build")
        context.ui.info("Built: pkg/puma-#{version}.gem")
        jruby_built = BuildSupport.new(context).build_jruby_gem(version)
        manual_jruby_instructions unless jruby_built
        context.events.publish(:checkpoint, kind: :wait_for_rubygems, version:, tag:)
        context.ui.info("STOP: push both gems to RubyGems, then rerun puma-release.")
        :wait_for_rubygems
      end

      private

      def retarget_draft_release_tag_if_needed(tag)
        head_sha = context.shell.output("git", "rev-parse", "HEAD").strip
        remote_sha = git_repo.remote_tag_sha(tag)
        return if remote_sha.empty? || remote_sha == head_sha

        release = github.release(tag)
        raise Error, "Remote tag #{tag} already exists at #{remote_sha}, not HEAD #{head_sha}." unless release&.fetch("isDraft", false)

        local_sha = context.shell.optional_output("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}^{commit}")
        context.shell.run("git", "tag", "-d", tag, allow_failure: true) unless local_sha.empty? || local_sha == head_sha
        context.shell.run("git", "tag", "--no-sign", tag) if local_sha.empty? || local_sha != head_sha
        context.ui.warn("Retargeting draft release tag #{tag} from #{remote_sha[0, 12]} to #{head_sha[0, 12]}...")
        context.shell.run("gh", "api", "-X", "DELETE", "repos/#{context.release_repo}/git/refs/tags/#{tag}")
      end

      def sync_release_target_to_head(tag)
        release = github.release(tag)
        return unless release

        head_sha = git_repo.head_sha
        return if release.fetch("targetCommitish", "") == head_sha

        context.ui.info("Updating release target for #{tag} to #{head_sha[0, 12]}...")
        github.edit_release_target(tag, head_sha)
      end

      def sync_release_title(tag, version)
        release = github.release(tag)
        return unless release

        title = repo_files.release_name(version)
        return if release.fetch("name", "") == title

        context.ui.info("Updating release title for #{tag} to #{title.inspect}...")
        github.edit_release_title(tag, title)
      end

      def manual_jruby_instructions
        context.ui.warn("JRuby gem was not built automatically.")
        puts "To build it manually, switch to JRuby and run:"
        puts "  bundle exec rake java gem"
      end
    end
  end
end
