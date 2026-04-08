# frozen_string_literal: true

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
        return wait_for_rubygems if step == :wait_for_rubygems
        return wait_for_merge if step == :wait_for_merge
        return complete if step == :complete
        return run_step(step) if confirm_step(step)

        :aborted
      end

      private

      def stage_detector = StageDetector.new(context)
      def git_repo = GitRepo.new(context)
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
        context.ui.info("A release PR is already in flight. Merge it, update local #{context.base_branch}, and rerun puma-release.")
        :wait_for_merge
      end
    end
  end
end
