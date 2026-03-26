# frozen_string_literal: true

module PumaRelease
  class ContributorResolver
    attr_reader :context, :git_repo, :github

    def initialize(context, git_repo: GitRepo.new(context), github: GitHubClient.new(context))
      @context = context
      @git_repo = git_repo
      @github = github
    end

    def codename_earner(tag)
      contributor = top_contributors_since(tag).first
      return nil unless contributor

      contributor.merge(login: resolve_login(tag, contributor))
    end

    def top_contributors_since(tag)
      git_repo.top_contributors_since_with_email(tag).map do |line|
        count, name, email = line.match(/^\s*(\d+)\s+(.+?)\s+<([^>]+)>$/)&.captures
        next unless count

        {count: count.to_i, name:, email:}
      end.compact
    end

    private

    def resolve_login(tag, contributor)
      logins = commits_for(tag, contributor).filter_map { |commit| github.commit_author_login(context.metadata_repo, commit.fetch(:sha)) }
      return most_common(logins) unless logins.empty?

      login_from_noreply_email(contributor.fetch(:email))
    end

    def commits_for(tag, contributor)
      git_repo.commit_authors_since(tag).select do |commit|
        commit.fetch(:name) == contributor.fetch(:name) && commit.fetch(:email) == contributor.fetch(:email)
      end
    end

    def most_common(values)
      values.tally.max_by { |_value, count| count }&.first
    end

    def login_from_noreply_email(email)
      email[%r{\A(?:\d+\+)?([^@]+)@users\.noreply\.github\.com\z}, 1]
    end
  end
end
