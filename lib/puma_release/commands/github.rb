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
        context.check_dependencies!("git", "gh")
        context.announce_live_mode!
        context.ensure_release_writes_allowed!
        git_repo.ensure_clean_main!
        version = repo_files.current_version
        tag = git_repo.release_tag(version)
        proposal_tag = git_repo.proposal_tag(version)
        artifact_paths = artifacts(version)
        body = repo_files.extract_history_section(version) || raise(Error, "Could not find section for #{version} in #{context.history_file}")
        title = repo_files.release_name(version)
        git_repo.ensure_release_tag_pushed!(tag)
        tag_sha = git_repo.local_tag_sha(tag)
        raise Error, "Local tag #{tag} is missing." if tag_sha.empty?

        release = ensure_release_for_final_tag(tag, proposal_tag, body, title, tag_sha)
        release = github.edit_release_target(tag, tag_sha) if release.fetch("targetCommitish", "") != tag_sha
        release = github.edit_release_title(tag, title) if release.fetch("name", "") != title
        release = github.edit_release_notes(tag, body) if release.fetch("body", "") != body
        github.upload_release_assets(tag, *artifact_paths)
        release = github.publish_release(tag) if release.fetch("isDraft", false)
        cleanup_proposal_release!(proposal_tag)
        context.events.publish(:release_published, tag:, url: release.fetch("url"))
        context.ui.info("GitHub release published: #{release.fetch('url')}")
        :complete
      end

      private

      def ensure_release_for_final_tag(tag, proposal_tag, body, title, tag_sha)
        release = github.release(tag)
        proposal_release = github.release(proposal_tag)
        raise Error, "Found both #{tag} and #{proposal_tag} releases. Clean up the proposal release before continuing." if release && proposal_release
        return release if release
        return promote_proposal_release!(proposal_tag, tag, tag_sha) if proposal_release

        github.create_release(tag, body, title:, draft: true)
      end

      def promote_proposal_release!(proposal_tag, tag, tag_sha)
        context.ui.info("Promoting draft release from #{proposal_tag} to #{tag}...")
        github.retag_release(proposal_tag, tag, target: tag_sha)
      end

      def cleanup_proposal_release!(proposal_tag)
        github.delete_release(proposal_tag, allow_failure: true) if github.release(proposal_tag)
        github.delete_tag_ref(proposal_tag, allow_failure: true) unless git_repo.remote_tag_sha(proposal_tag).empty?
      end

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
