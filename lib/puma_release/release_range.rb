# frozen_string_literal: true

module PumaRelease
  class ReleaseRange
    attr_reader :context, :last_tag

    def initialize(context, last_tag)
      @context = context
      @last_tag = last_tag
    end

    def items
      @items ||= begin
        seen_prs = {}
        commits.filter_map do |commit|
          pr = github.commit_pulls(context.metadata_repo, commit.fetch(:sha)).first
          if pr
            next if seen_prs[pr.fetch("number")]

            seen_prs[pr.fetch("number")] = true
            pull_request_item(pr, commit.fetch(:sha))
          else
            commit.merge(type: "commit")
          end
        end
      end
    end

    def to_prompt_context
      lines = ["Repository: #{context.metadata_repo}", "Release range: #{last_tag}..HEAD", "", "Changes:"]
      items.each do |item|
        if item.fetch(:type) == "pr"
          labels = item.fetch(:labels)
          lines << "- PR ##{item.fetch(:number)} #{item.fetch(:title)}"
          lines << "  Labels: #{labels.empty? ? "none" : labels.join(", ")}"
          lines << "  PR URL: #{item.fetch(:url)}"
          lines << "  Merge commit: #{item.fetch(:commit_url)}"
        else
          lines << "- Commit #{item.fetch(:sha)[0, 12]} #{item.fetch(:subject)}"
          lines << "  Commit URL: #{item.fetch(:commit_url)}"
        end
      end
      lines.join("\n")
    end

    private

    def commits
      shell.output("git", "log", "--reverse", "--format=%H%x09%s", "#{last_tag}..HEAD").lines(chomp: true).map do |line|
        sha, subject = line.split("\t", 2)
        {sha:, subject:, commit_url: "https://github.com/#{context.metadata_repo}/commit/#{sha}"}
      end
    end

    def pull_request_item(pr, sha)
      {
        type: "pr",
        number: pr.fetch("number"),
        title: pr.fetch("title"),
        url: pr.fetch("html_url"),
        commit_url: "https://github.com/#{context.metadata_repo}/commit/#{sha}",
        labels: Array(pr["labels"]).map { |label| label.fetch("name") }
      }
    end

    def shell = context.shell
    def github = @github ||= GitHubClient.new(context)
  end
end
