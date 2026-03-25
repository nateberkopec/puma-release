# frozen_string_literal: true

module PumaRelease
  module Commands
    class Prepare
      attr_reader :context, :git_repo, :repo_files, :github, :contributors

      def initialize(context)
        @context = context
        @git_repo = GitRepo.new(context)
        @repo_files = RepoFiles.new(context)
        @github = GitHubClient.new(context)
        @contributors = ContributorResolver.new(context, git_repo:, github:)
      end

      def call
        context.check_dependencies!("git", "gh", context.agent_binary)
        context.announce_live_mode!
        context.ensure_release_writes_allowed!
        git_repo.ensure_clean_main!
        ensure_green_ci!

        last_tag = git_repo.last_tag
        context.ui.info("Last release tag: #{last_tag}")
        release_range = ReleaseRange.new(context, last_tag)
        recommendation = VersionRecommender.new(context, release_range).call
        bump_type = recommendation.fetch("bump_type")
        current_version = repo_files.current_version
        new_version = git_repo.bump_version(current_version, bump_type)
        context.ui.info("Version bump: #{current_version} -> #{new_version}")
        show_version_recommendation(recommendation)

        earner = show_codename_earner(last_tag, bump_type)
        changelog = prepare_changelog(release_range, new_version, last_tag)
        context.ui.info("Generating link references...")
        refs = LinkReferenceBuilder.new(context).build(changelog)
        repo_files.prepend_history_section!(new_version, changelog, refs)
        repo_files.update_version!(new_version, bump_type, codename: context.codename)

        branch = "release-v#{new_version}"
        git_repo.checkout_release_branch!(branch)
        git_repo.commit_release!(new_version)
        git_repo.push_branch!(branch)

        compare_url = "https://github.com/#{context.metadata_repo}/compare/#{last_tag}...#{git_repo.head_sha}"
        pr_url = github.create_release_pr("Release v#{new_version}", branch, body: compare_url)
        github.comment_on_pr(pr_url, pr_comment(recommendation, earner))
        release = ensure_draft_release(new_version, branch)
        release_url = release.fetch("url")
        github.update_pr_body(pr_url, "#{compare_url}\n\n#{release_url}")
        context.events.publish(:checkpoint, kind: :wait_for_merge, pr_url:, release_url:, branch:)

        context.ui.info("Release PR created: #{pr_url}")
        context.ui.info("Draft GitHub release ready: #{release.fetch('url')}")
        context.ui.warn(waiting_on_codename_message(earner)) if earner
        context.ui.info("STOP: review and merge the PR, then rerun puma-release.")
        :wait_for_merge
      end

      private

      def ensure_green_ci!
        return context.ui.warn("Skipping CI check because --skip-ci-check was set.") if context.skip_ci_check?

        context.ui.info("Checking CI status for HEAD...")
        ci_checker.ensure_green!(git_repo.head_sha)
      end

      def ci_checker = CiChecker.new(context)

      def show_codename_earner(last_tag, bump_type)
        return nil if bump_type == "patch"
        return nil if context.codename

        context.ui.info("Top contributors since #{last_tag}:")
        git_repo.top_contributors_since(last_tag).first(5).each { |line| puts line }
        earner = contributors.codename_earner(last_tag)
        return nil unless earner

        label = earner.fetch(:name)
        label += " (@#{earner[:login]})" if earner[:login]
        context.ui.info("Codename earner: #{label}")
        earner
      end

      def show_version_recommendation(recommendation)
        context.ui.info("Version bump recommendation:")
        puts recommendation.fetch("reasoning_markdown")

        breaking_changes = recommendation.fetch("breaking_changes", [])
        return if breaking_changes.empty?

        context.ui.warn("Potential breaking changes:")
        breaking_changes.each { |item| puts "- #{item}" }
      end

      def prepare_changelog(release_range, new_version, last_tag)
        tag = git_repo.proposal_tag(new_version)
        git_repo.create_signed_tag!(tag, message: "Temporary changelog tag for #{tag}")
        ChangelogGenerator.new(context, release_range, new_tag: tag, last_tag:).call
      ensure
        git_repo.delete_local_tag!(tag, allow_failure: true) if tag
      end

      def ensure_draft_release(version, branch)
        tag = git_repo.proposal_tag(version)
        body = release_body(version)
        title = repo_files.release_name(version)
        release = github.release(tag)
        release ||= github.create_release(tag, body, title:, draft: true, target: branch)
        release = github.edit_release_target(tag, branch) if release.fetch("targetCommitish", "") != branch
        release = github.edit_release_title(tag, title) if release.fetch("name", "") != title
        release.fetch("body", "") == body ? release : github.edit_release_notes(tag, body)
      end

      def pr_comment(recommendation, earner)
        lines = [
          context.comment_attribution(recommendation.fetch("model_name", context.comment_author_model_name)),
          "",
          "## Version bump recommendation",
          "",
          "Recommended bump: **#{recommendation.fetch('bump_type')}**",
          "",
          recommendation.fetch("reasoning_markdown")
        ]

        breaking_changes = recommendation.fetch("breaking_changes", [])
        if breaking_changes.any?
          lines += ["", "## Potential breaking changes", ""]
          lines += breaking_changes.map { |item| "- #{item}" }
        else
          lines += ["", "## Potential breaking changes", "", "_None identified._"]
        end

        return lines.join("\n") unless earner

        [*lines, "", "## Codename", "", codename_message(earner)].join("\n")
      end

      def codename_message(earner)
        return "@#{earner.fetch(:login)} earned the codename for this release. Please propose a codename!" if earner[:login]

        "#{earner.fetch(:name)} earned the codename for this release. Please propose a codename!"
      end

      def waiting_on_codename_message(earner)
        return "Waiting on @#{earner.fetch(:login)} for a codename before merging." if earner[:login]

        "Waiting on #{earner.fetch(:name)} for a codename before merging."
      end

      def release_body(version)
        repo_files.extract_history_section(version) || raise(Error, "Could not find section for #{version} in #{context.history_file}")
      end
    end
  end
end
