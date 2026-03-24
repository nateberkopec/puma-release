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
      debug("ensure_green! called with sha=#{sha}")
      status = combined_status(sha)
      debug("combined_status returned: #{status.inspect}")
      return context.ui.info("CI is green.") if status == :success
      return handle_unknown if status == :unknown

      raise Error, "CI for #{sha[0, 12]} is #{status}. Stop and investigate before releasing."
    end

    private

    def combined_status(sha)
      status_url = "repos/#{context.metadata_repo}/commits/#{sha}/status"
      runs_url = "repos/#{context.metadata_repo}/commits/#{sha}/check-runs"

      debug("fetching commit status from: #{status_url}")
      statuses = gh_json("gh", "api", status_url) || {}
      debug("commit status response keys: #{statuses.keys.inspect}")
      debug("commit status state: #{statuses["state"].inspect}")
      debug("statuses array length: #{Array(statuses["statuses"]).length}")
      Array(statuses["statuses"]).each_with_index do |item, i|
        debug("  status[#{i}]: context=#{item["context"].inspect} state=#{item["state"].inspect}")
      end

      debug("fetching check-runs from: #{runs_url}")
      runs = gh_json("gh", "api", runs_url) || {}
      debug("check-runs response keys: #{runs.keys.inspect}")
      debug("check_runs array length: #{Array(runs["check_runs"]).length}")
      Array(runs["check_runs"]).each_with_index do |run, i|
        debug("  check_run[#{i}]: name=#{run["name"].inspect} status=#{run["status"].inspect} conclusion=#{run["conclusion"].inspect}")
      end

      contexts = Array(statuses["statuses"]).map { |item| item.fetch("state") }
      conclusions = Array(runs["check_runs"]).flat_map { |run| [run["status"], run["conclusion"]].compact }
      values = contexts + conclusions

      debug("contexts from statuses: #{contexts.inspect}")
      debug("conclusions from check-runs: #{conclusions.inspect}")
      debug("combined values: #{values.inspect}")

      if values.empty?
        debug("returning :unknown — no values found")
        return :unknown
      end

      failure_values = values.select { |v| FAILURE_CONCLUSIONS.include?(v) || v == "error" }
      if failure_values.any?
        debug("returning :failure — found failure values: #{failure_values.inspect}")
        return :failure
      end

      pending_values = values.select { |v| PENDING_STATUSES.include?(v) }
      if pending_values.any?
        debug("returning :pending — found pending values: #{pending_values.inspect}")
        return :pending
      end

      unrecognized = values - ["success", "neutral", "skipped", "completed"]
      if unrecognized.empty?
        debug("returning :success — all values recognized as success: #{values.inspect}")
        return :success
      end

      debug("returning :unknown — unrecognized values: #{unrecognized.inspect}")
      :unknown
    end

    def handle_unknown
      return context.ui.warn("Could not determine CI status; continuing because --allow-unknown-ci was set.") if context.allow_unknown_ci?
      raise Error, "Could not determine CI status. Re-run with --allow-unknown-ci if you want to proceed anyway."
    end

    def gh_json(*command)
      debug("gh_json running: #{command.join(" ")}")
      result = context.shell.run(*command, allow_failure: true)
      debug("gh_json exit status: #{result.exitstatus}, success: #{result.success?}")
      unless result.success?
        debug("gh_json stderr: #{result.stderr.strip.inspect}")
        debug("gh_json stdout: #{result.stdout.strip.inspect}")
        return nil
      end

      body = result.stdout.strip
      debug("gh_json response body (first 500 chars): #{body[0, 500].inspect}")
      body.empty? ? {} : JSON.parse(body)
    end

    def debug(message)
      context.ui.debug(message) if context.debug?
    end
  end
end
