# frozen_string_literal: true

require "json"

module PumaRelease
  class CiChecker
    FAILURE_CONCLUSIONS = %w[failure cancelled timed_out action_required startup_failure stale].freeze
    PENDING_STATUSES = %w[queued in_progress pending waiting requested].freeze

    attr_reader :context

    def initialize(context)
      @context = context
    end

    def ensure_green!(sha)
      status = combined_status(sha)
      return context.ui.info("CI is green.") if status == :success
      return handle_unknown if status == :unknown

      raise Error, "CI for #{sha[0, 12]} is #{status}. Stop and investigate before releasing."
    end

    private

    def combined_status(sha)
      statuses = gh_json("gh", "api", "repos/#{context.release_repo}/commits/#{sha}/status") || {}
      runs = gh_json("gh", "api", "repos/#{context.release_repo}/commits/#{sha}/check-runs") || {}
      contexts = Array(statuses["statuses"]).map { |item| item.fetch("state") }
      conclusions = Array(runs["check_runs"]).flat_map { |run| [run["status"], run["conclusion"]].compact }
      values = contexts + conclusions
      return :unknown if values.empty?
      return :failure if values.any? { |value| FAILURE_CONCLUSIONS.include?(value) || value == "error" }
      return :pending if values.any? { |value| PENDING_STATUSES.include?(value) }
      return :success if (values - ["success", "neutral", "skipped", "completed"]).empty?

      :unknown
    end

    def handle_unknown
      return context.ui.warn("Could not determine CI status; continuing because --allow-unknown-ci was set.") if context.allow_unknown_ci?
      raise Error, "Could not determine CI status. Re-run with --allow-unknown-ci if you want to proceed anyway."
    end

    def gh_json(*command)
      result = context.shell.run(*command, allow_failure: true)
      return nil unless result.success?

      body = result.stdout.strip
      body.empty? ? {} : JSON.parse(body)
    end
  end
end
