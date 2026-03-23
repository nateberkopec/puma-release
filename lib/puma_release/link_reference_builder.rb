# frozen_string_literal: true

module PumaRelease
  class LinkReferenceBuilder
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def build(changelog)
      numbers = changelog.scan(/\[#(\d+)\]/).flatten.map(&:to_i).uniq.sort.reverse
      existing = context.history_file.read
      numbers.filter_map { |number| reference_for(number, existing) }.join("\n")
    end

    private

    def reference_for(number, existing)
      return if existing.match?(/^\[##{number}\]:/)

      context.ui.info("  Looking up ##{number}...")
      pr = github.pr(number, repo: context.metadata_repo)
      return pr_reference(number, pr) if pr

      issue = github.issue(number, repo: context.metadata_repo)
      return issue_reference(number, issue) if issue

      context.ui.warn("Could not look up ##{number}")
      nil
    end

    def pr_reference(number, pr)
      login = pr.dig("author", "login")
      author = github.user(login)&.fetch("name", nil).to_s
      author = login if author.empty?
      merged_at = pr.fetch("mergedAt", "").split("T").first
      "[##{number}]:https://github.com/#{context.metadata_repo}/pull/#{number}     \"PR by #{author}, merged #{merged_at}\""
    end

    def issue_reference(number, issue)
      login = issue.dig("author", "login")
      closed_at = issue.fetch("closedAt", "").split("T").first
      "[##{number}]:https://github.com/#{context.metadata_repo}/issues/#{number}     \"Issue by @#{login}, closed #{closed_at}\""
    end

    def github = @github ||= GitHubClient.new(context)
  end
end
