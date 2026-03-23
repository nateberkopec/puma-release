# frozen_string_literal: true

module PumaRelease
  module Commands
    class Prepare
      attr_reader :context, :git_repo, :repo_files, :github

      def initialize(context)
        @context = context
        @git_repo = GitRepo.new(context)
        @repo_files = RepoFiles.new(context)
        @github = GitHubClient.new(context)
      end

      def call
        context.check_dependencies!("git", "gh", context.agent_binary)
        git_repo.ensure_clean_main!
        context.ui.info("Checking CI status for HEAD...")
        CiChecker.new(context).ensure_green!(git_repo.head_sha)

        last_tag = git_repo.last_tag
        context.ui.info("Last release tag: #{last_tag}")
        release_range = ReleaseRange.new(context, last_tag)
        recommendation = VersionRecommender.new(context, release_range).call
        bump_type = recommendation.fetch("bump_type")
        current_version = repo_files.current_version
        new_version = git_repo.bump_version(current_version, bump_type)
        context.ui.info("Version bump: #{current_version} -> #{new_version}")

        earner = show_codename_earner(last_tag, bump_type)
        changelog = prepare_changelog(release_range, new_version, last_tag)
        context.ui.info("Generating link references...")
        refs = LinkReferenceBuilder.new(context).build(changelog)
        repo_files.prepend_history_section!(new_version, changelog, refs)
        repo_files.update_version!(new_version, bump_type)

        branch = "release-v#{new_version}"
        git_repo.checkout_release_branch!(branch)
        git_repo.commit_release!(new_version)
        git_repo.push_branch!(branch)

        pr_url = github.create_release_pr("Release v#{new_version}", branch)
        github.comment_on_pr(pr_url, pr_comment(recommendation, earner))
        release = ensure_draft_release(new_version, branch)
        context.events.publish(:checkpoint, kind: :wait_for_merge, pr_url:, release_url: release.fetch("url"), branch:)

        context.ui.info("Release PR created: #{pr_url}")
        context.ui.info("Draft GitHub release ready: #{release.fetch('url')}")
        context.ui.warn("Waiting on @#{earner} for a codename before merging.") if earner
        context.ui.info("STOP: review and merge the PR, then rerun puma-release.")
        :wait_for_merge
      end

      private

      def show_codename_earner(last_tag, bump_type)
        return nil if bump_type == "patch"

        context.ui.info("Top contributors since #{last_tag}:")
        git_repo.top_contributors_since(last_tag).first(5).each { |line| puts line }
        earner = git_repo.codename_earner(last_tag)
        context.ui.info("Codename earner: #{earner}")
        earner
      end

      def prepare_changelog(release_range, new_version, last_tag)
        tag = git_repo.release_tag(new_version)
        context.shell.run("git", "tag", tag, "HEAD")
        ChangelogGenerator.new(context, release_range, new_tag: tag, last_tag:).call
      ensure
        context.shell.run("git", "tag", "-d", tag, allow_failure: true) if tag
      end

      def ensure_draft_release(version, branch)
        tag = git_repo.release_tag(version)
        body = release_body(version)
        release = github.release(tag)
        release ||= github.create_release(tag, body, draft: true, target: branch)
        release.fetch("body", "") == body ? release : github.edit_release_notes(tag, body)
      end

      def pr_comment(recommendation, earner)
        lines = [
          "## Version bump recommendation",
          "",
          "Recommended bump: **#{recommendation.fetch('bump_type')}**",
          "",
          recommendation.fetch("reasoning_markdown")
        ]
        return lines.join("\n") unless earner

        [*lines, "", "## Codename", "", "@#{earner} earned the codename for this release. Please propose a codename!"].join("\n")
      end

      def release_body(version)
        repo_files.extract_history_section(version) || raise(Error, "Could not find section for #{version} in #{context.history_file}")
      end
    end
  end
end
