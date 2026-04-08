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
        return prepare_follow_up if step == :prepare_follow_up
        return wait_for_merge if step == :wait_for_merge
        return complete if step == :complete
        return run_step(step) if confirm_step(step)

        :aborted
      end

      private

      def stage_detector = StageDetector.new(context)
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

      def prepare_follow_up
        prepare_command.resume_follow_up
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
