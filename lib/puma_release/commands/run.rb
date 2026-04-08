# frozen_string_literal: true

require "shellwords"

module PumaRelease
  module Commands
    class Run
      attr_reader :context

      def initialize(context)
        @context = context
      end

      def call
        step = stage_detector.next_step
        return recover_prepare if step == :recover_prepare
        return orphaned_release_branch if step == :orphaned_release_branch
        return prepare_follow_up if step == :prepare_follow_up
        return recover_build if step == :recover_build
        return wait_for_rubygems if step == :wait_for_rubygems
        return wait_for_merge if step == :wait_for_merge
        return complete if step == :complete
        return run_step(step) if confirm_step(step)

        :aborted
      end

      private

      def stage_detector = StageDetector.new(context)
      def git_repo = GitRepo.new(context)
      def github = GitHubClient.new(context)
      def prepare_command = Prepare.new(context)

      def confirm_step(step)
        return true if context.yes?

        context.ui.confirm("Detected next step: #{step}. Continue?")
      end

      def run_step(step)
        case step
        when :prepare then prepare_command.call
        when :build then Build.new(context).call
        when :github then Github.new(context).call
        else raise Error, "Unknown step: #{step}"
        end
      end

      def recover_prepare
        return :aborted unless confirm_step(:prepare)

        base_branch = git_repo.release_branch_base
        context.ui.info("Found a local release branch with no open PR. Switching back to #{base_branch} and retrying prepare.")
        git_repo.checkout_branch!(base_branch)
        run_step(:prepare)
      end

      def orphaned_release_branch
        context.ui.info("Found a local release branch with no open PR, but puma-release does not know which base branch to return to. Switch back to your base branch and rerun with --base-branch if needed.")
        :orphaned_release_branch
      end

      def recover_build
        return :aborted unless confirm_step(:build)

        context.ui.info("Found a merged release branch. Switching back to #{context.base_branch}, updating it, and continuing with build.")
        git_repo.update_local_branch!(context.base_branch)
        run_step(:build)
      end

      def prepare_follow_up
        prepare_command.resume_follow_up
      end

      def wait_for_rubygems
        context.ui.info("Release artifacts are built, but RubyGems does not show both variants yet. Push both gems to RubyGems, wait for them to appear, and rerun puma-release.")
        :wait_for_rubygems
      end

      def complete
        context.ui.info("The current release is already complete. No action needed.")
        :complete
      end

      def wait_for_merge
        pr = github.open_release_pr
        return merge_release_pr_and_continue(pr) if interactive_release_pr_merge?(pr)

        context.ui.info(wait_for_merge_message(pr))
        :wait_for_merge
      end

      def wait_for_merge_message(pr)
        url = pr&.fetch("url", "").to_s
        message = "A release PR is already in flight"
        message += " (#{url})" unless url.empty?
        "#{message}. Merge it, update local #{context.base_branch}, and rerun puma-release."
      end

      def interactive_release_pr_merge?(pr)
        return false unless pr
        return false unless context.live?
        return false unless context.release_repo == context.metadata_repo
        return false if context.yes?
        return false unless $stdin.tty?

        prompt_to_merge_release_pr?(pr)
      end

      def prompt_to_merge_release_pr?(pr)
        return gum_merge_prompt?(pr) if context.shell.available?("gum")

        context.ui.confirm("Release PR ready: #{pr.fetch("url")}. Merge it now and continue?", default: false)
      end

      def gum_merge_prompt?(pr)
        command = Shellwords.join([
          "gum", "choose",
          "--header", "Release PR ready: #{pr.fetch("url")}\nMerge it now and continue?",
          "Merge release PR now",
          "Not yet"
        ])
        result = context.shell.run("sh", "-lc", "#{command} < /dev/tty 2> /dev/tty", allow_failure: true)
        result.success? && result.stdout.strip == "Merge release PR now"
      end

      def merge_release_pr_and_continue(pr)
        context.ui.info("Merging release PR: #{pr.fetch("url")}")
        github.merge_pr(pr.fetch("url"))
        git_repo.update_local_branch!(context.base_branch)
        context.ui.info("Merged release PR and updated local #{context.base_branch}. Continuing with the release.")
        call
      end
    end
  end
end
