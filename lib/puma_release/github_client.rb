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

    def open_release_pr(branch = nil)
      release_pr("open", branch)
    end

    def merged_release_pr(branch = nil)
      release_pr("merged", branch)
    end

    def create_release_pr(title, branch, body: "")
      output_gh!(
        "pr", "create",
        "--repo", context.release_repo,
        "--base", context.base_branch,
        "--head", branch,
        "--title", title,
        "--body", body
      ).strip
    end

    def comment_on_pr(pr_url, body)
      run_gh!("pr", "comment", pr_url, "--body", body)
    end

    def merge_pr(pr)
      run_gh!("pr", "merge", pr.to_s, "--repo", context.release_repo, "--merge", "--delete-branch=false")
    end

    def release(tag)
      json("gh", "release", "view", tag, "--repo", context.release_repo, "--json", "tagName,name,isDraft,body,url,assets,targetCommitish")
    end

    def create_release(tag, body, title: tag, draft: true)
      with_notes_file(body) do |path|
        command = ["release", "create", tag, "--repo", context.release_repo, "--title", title, "--notes-file", path]
        command << "--draft" if draft
        run_gh!(*command)
      end
      release(tag)
    end

    def edit_release_notes(tag, body)
      with_notes_file(body) { |path| run_gh!("release", "edit", tag, "--repo", context.release_repo, "--notes-file", path) }
      release(tag)
    end

    def edit_release_target(tag, target)
      run_gh!("release", "edit", tag, "--repo", context.release_repo, "--target", target)
      release(tag)
    end

    def edit_release_title(tag, title)
      run_gh!("release", "edit", tag, "--repo", context.release_repo, "--title", title)
      release(tag)
    end

    def publish_release(tag)
      run_gh!("release", "edit", tag, "--repo", context.release_repo, "--draft=false")
      release(tag)
    end

    def upload_release_assets(tag, *paths)
      run_gh!("release", "upload", tag, "--repo", context.release_repo, "--clobber", *paths)
    end

    private

    def json(*command)
      result = context.shell.run(*command, allow_failure: true)
      return nil unless result.success?

      body = result.stdout.strip
      body.empty? ? {} : JSON.parse(body)
    end

    def run_gh!(*command, **options)
      context.confirm_live_gh_command!("gh", *command) if context.respond_to?(:confirm_live_gh_command!)
      context.shell.run("gh", *command, **options)
    end

    def output_gh!(*command, **options)
      context.confirm_live_gh_command!("gh", *command) if context.respond_to?(:confirm_live_gh_command!)
      context.shell.output("gh", *command, **options)
    end

    def release_pr(state, branch = nil)
      owner = context.release_repo.split("/").first
      search_branch = branch || "release-v"
      queries = ["head:#{owner}:#{search_branch}", "head:#{search_branch}"].uniq
      prs = queries.flat_map do |query|
        json(
          "gh", "pr", "list", "--repo", context.release_repo,
          "--state", state,
          "--search", query,
          "--json", "number,title,url,headRefName,baseRefName,mergedAt"
        ) || []
      end

      prs = prs.uniq { |pr| pr.fetch("number", pr.fetch("url", pr.object_id)) }
      return prs.find { |pr| pr.fetch("headRefName", "") == branch } if branch

      prs.find { |pr| pr.fetch("headRefName", "").start_with?("release-v") }
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
