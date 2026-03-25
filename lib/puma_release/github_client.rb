# frozen_string_literal: true

require "json"
require "tempfile"

module PumaRelease
  class GitHubClient
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def commit_pulls(repo, sha)
      json("gh", "api", "repos/#{repo}/commits/#{sha}/pulls") || []
    end

    def commit_author_login(repo, sha)
      commit = json("gh", "api", "repos/#{repo}/commits/#{sha}")
      login = commit&.dig("author", "login") || commit&.dig("committer", "login")
      return login if login && !login.empty?

      commit_pulls(repo, sha).first&.dig("user", "login")
    end

    def pr(number, repo: context.release_repo)
      json("gh", "pr", "view", number.to_s, "--repo", repo, "--json", "number,title,url,state,mergedAt,author,labels,headRefName")
    end

    def issue(number, repo: context.metadata_repo)
      json("gh", "issue", "view", number.to_s, "--repo", repo, "--json", "number,title,url,closedAt,author")
    end

    def user(login)
      json("gh", "api", "users/#{login}")
    end

    def open_release_pr
      owner = context.release_repo.split("/").first
      prs = json(
        "gh", "pr", "list", "--repo", context.release_repo,
        "--state", "open",
        "--search", "head:#{owner}:release-v",
        "--json", "number,title,url,headRefName"
      ) || []
      prs.find { |pr| pr.fetch("headRefName", "").start_with?("release-v") }
    end

    def create_release_pr(title, branch, body: "")
      context.shell.output(
        "gh", "pr", "create",
        "--repo", context.release_repo,
        "--base", "main",
        "--head", branch,
        "--title", title,
        "--body", body
      ).strip
    end

    def comment_on_pr(pr_url, body)
      context.shell.run("gh", "pr", "comment", pr_url, "--body", body)
    end

    def release(tag)
      json("gh", "release", "view", tag, "--repo", context.release_repo, "--json", "tagName,name,isDraft,body,url,assets,targetCommitish")
    end

    def create_release(tag, body, title: tag, draft: true, target: nil)
      with_notes_file(body) do |path|
        command = ["gh", "release", "create", tag, "--repo", context.release_repo, "--title", title, "--notes-file", path]
        command += ["--target", target] if target
        command << "--draft" if draft
        context.shell.run(*command)
      end
      release(tag)
    end

    def edit_release_notes(tag, body)
      with_notes_file(body) { |path| context.shell.run("gh", "release", "edit", tag, "--repo", context.release_repo, "--notes-file", path) }
      release(tag)
    end

    def edit_release_target(tag, target)
      context.shell.run("gh", "release", "edit", tag, "--repo", context.release_repo, "--target", target)
      release(tag)
    end

    def edit_release_title(tag, title)
      context.shell.run("gh", "release", "edit", tag, "--repo", context.release_repo, "--title", title)
      release(tag)
    end

    def publish_release(tag)
      context.shell.run("gh", "release", "edit", tag, "--repo", context.release_repo, "--draft=false")
      release(tag)
    end

    def upload_release_assets(tag, *paths)
      context.shell.run("gh", "release", "upload", tag, "--repo", context.release_repo, "--clobber", *paths)
    end

    private

    def json(*command)
      result = context.shell.run(*command, allow_failure: true)
      return nil unless result.success?

      body = result.stdout.strip
      body.empty? ? {} : JSON.parse(body)
    end

    def with_notes_file(body)
      Tempfile.create("puma-release-notes") do |file|
        file.write(body)
        file.flush
        yield file.path
      end
    end
  end
end
