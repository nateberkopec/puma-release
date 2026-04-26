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
        git_repo.ensure_clean_base!
        ensure_green_ci!

        last_tag = git_repo.last_tag
        context.ui.info("Last release tag: #{last_tag}")
        release_range = ReleaseRange.new(context, last_tag)
        current_version = repo_files.current_version
        recommendation = version_recommendation(release_range, current_version)
        bump_type = recommendation.fetch("bump_type")
        new_version = recommendation.fetch("version") { git_repo.bump_version(current_version, bump_type) }
        context.ui.info("Version bump: #{current_version} -> #{new_version}")
        show_version_recommendation(recommendation)

        earner = show_codename_earner(last_tag, bump_type)
        changelog = prepare_changelog(release_range, new_version, last_tag)
        context.ui.info("Generating link references...")
        refs = build_link_references(changelog)

        branch = "release-v#{new_version}"
        git_repo.checkout_release_branch!(branch, base_branch: context.base_branch)
        repo_files.prepend_history_section!(new_version, changelog, refs)
        repo_files.update_version!(new_version, bump_type, codename: context.codename)
        upgrade_guide_path = write_upgrade_guide(release_range, new_version, recommendation, bump_type)
        security_file = update_security_policy(new_version, bump_type)
        git_repo.commit_release!(new_version, extra_files: [*Array(upgrade_guide_path), *Array(security_file)])
        git_repo.push_branch!(branch)

        compare_url = "https://github.com/#{context.metadata_repo}/compare/#{last_tag}...#{git_repo.head_sha}"
        pr_url = github.create_release_pr("Release v#{new_version}", branch, body: compare_url)
        github.comment_on_pr(pr_url, pr_comment(recommendation, earner))
        context.events.publish(:checkpoint, kind: :wait_for_merge, pr_url:, branch:)

        context.ui.info("Release PR created: #{pr_url}")
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

      def recommend_version(release_range)
        VersionRecommender.new(context, release_range).call
      end

      def version_recommendation(release_range, current_version)
        return recommend_version(release_range) unless context.forced_version

        forced_version_recommendation(current_version)
      end

      def forced_version_recommendation(current_version)
        forced_version = context.forced_version.strip
        bump_type = infer_forced_bump_type(current_version, forced_version)
        context.ui.warn("Skipping AI version recommendation because --release-version was set.")

        {
          "version" => forced_version,
          "bump_type" => bump_type,
          "reasoning_markdown" => "Release version was manually forced to `#{forced_version}` with `--release-version`.",
          "breaking_changes" => [],
          "manual_override" => true
        }
      end

      def infer_forced_bump_type(current_version, forced_version)
        current = parse_semver(current_version)
        forced = parse_semver(forced_version)
        raise Error, "Forced release version #{forced_version} must be greater than current version #{current_version}" unless (forced <=> current).positive?

        return "major" if forced[0] > current[0]
        return "minor" if forced[1] > current[1]

        "patch"
      end

      def parse_semver(version)
        match = version.match(/\A(\d+)\.(\d+)\.(\d+)\z/)
        raise Error, "Release version must be in X.Y.Z format: #{version}" unless match

        match.captures.map(&:to_i)
      end

      def build_link_references(changelog)
        LinkReferenceBuilder.new(context).build(changelog)
      end

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

      def update_security_policy(new_version, bump_type)
        return nil unless bump_type == "major"

        repo_files.update_security!(new_version)
        context.security_file
      end

      def write_upgrade_guide(release_range, new_version, recommendation, bump_type)
        return nil unless bump_type == "major"

        UpgradeGuideWriter.new(
          context,
          release_range,
          new_version:,
          breaking_changes: recommendation.fetch("breaking_changes", []),
          codename: context.codename
        ).call
      end

      def prepare_changelog(release_range, new_version, last_tag)
        ChangelogGenerator.new(context, release_range, new_tag: git_repo.release_tag(new_version), last_tag:).call
      end

      def pr_comment(recommendation, earner)
        lines = [
          *pr_comment_attribution(recommendation),
          "## Version bump recommendation",
          "",
          "Recommended bump: **#{recommendation.fetch("bump_type")}**",
          "",
          recommendation.fetch("reasoning_markdown")
        ]

        breaking_changes = recommendation.fetch("breaking_changes", [])
        if recommendation.fetch("manual_override", false)
          lines += ["", "## Potential breaking changes", "", "_Skipped because the version was selected manually._"]
        elsif breaking_changes.any?
          lines += ["", "## Potential breaking changes", ""]
          lines += breaking_changes.map { |item| "- #{item}" }
        else
          lines += ["", "## Potential breaking changes", "", "_None identified._"]
        end

        return lines.join("\n") unless earner

        [*lines, "", "## Codename", "", codename_message(earner)].join("\n")
      end

      def pr_comment_attribution(recommendation)
        return [] if recommendation.fetch("manual_override", false)

        [context.comment_attribution(recommendation.fetch("model_name", context.comment_author_model_name)), ""]
      end

      def codename_message(earner)
        return "@#{earner.fetch(:login)} earned the codename for this release. Please propose a codename!" if earner[:login]

        "#{earner.fetch(:name)} earned the codename for this release. Please propose a codename!"
      end

      def waiting_on_codename_message(earner)
        return "Waiting on @#{earner.fetch(:login)} for a codename before merging." if earner[:login]

        "Waiting on #{earner.fetch(:name)} for a codename before merging."
      end
    end
  end
end
