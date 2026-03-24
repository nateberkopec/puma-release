# frozen_string_literal: true

module PumaRelease
  module Commands
    class Github
      attr_reader :context, :git_repo, :repo_files, :github

      def initialize(context)
        @context = context
        @git_repo = GitRepo.new(context)
        @repo_files = RepoFiles.new(context)
        @github = GitHubClient.new(context)
      end

      def call
        context.check_dependencies!("gh")
        context.announce_live_mode!
        context.ensure_release_writes_allowed!
        version = repo_files.current_version
        tag = git_repo.release_tag(version)
        body = repo_files.extract_history_section(version) || raise(Error, "Could not find section for #{version} in #{context.history_file}")
        title = repo_files.release_name(version)
        release = github.release(tag)
        release ||= github.create_release(tag, body, title:, draft: true)
        head_sha = git_repo.head_sha
        release = github.edit_release_target(tag, head_sha) if release.fetch("targetCommitish", "") != head_sha
        release = github.edit_release_title(tag, title) if release.fetch("name", "") != title
        release = github.edit_release_notes(tag, body) if release.fetch("body", "") != body
        release = github.publish_release(tag) if release.fetch("isDraft", false)
        github.upload_release_assets(tag, *artifacts(version))
        context.events.publish(:release_published, tag:, url: release.fetch("url"))
        context.ui.info("GitHub release published: #{release.fetch('url')}")
        :complete
      end

      private

      def artifacts(version)
        paths = [
          context.repo_dir.join("pkg", "puma-#{version}.gem"),
          context.repo_dir.join("pkg", "puma-#{version}-java.gem")
        ]
        missing = paths.reject(&:file?)
        raise Error, "Missing release artifact(s): #{missing.join(' ')}" unless missing.empty?

        paths.map(&:to_s)
      end
    end
  end
end
