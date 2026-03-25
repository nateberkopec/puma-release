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
      output_gh!(
        "pr", "create",
        "--repo", context.release_repo,
        "--base", "main",
        "--head", branch,
        "--title", title,
        "--body", body
      ).strip
    end

    def update_pr_body(pr_url, body)
      run_gh!("pr", "edit", pr_url, "--body", body)
    end

    def comment_on_pr(pr_url, body)
      run_gh!("pr", "comment", pr_url, "--body", body)
    end

    def release(tag)
      json("gh", "release", "view", tag, "--repo", context.release_repo, "--json", "tagName,name,isDraft,body,url,assets,targetCommitish")
    end

    def retag_release(old_tag, new_tag, target: nil)
      release_id = release_id(old_tag)
      command = ["api", "-X", "PATCH", "repos/#{context.release_repo}/releases/#{release_id}", "-f", "tag_name=#{new_tag}"]
      command += ["-f", "target_commitish=#{target}"] if target
      run_gh!(*command)
      release(new_tag)
    end

    def delete_release(tag, allow_failure: false)
      release_id = release_id(tag, allow_failure:)
      return false unless release_id

      run_gh!("api", "-X", "DELETE", "repos/#{context.release_repo}/releases/#{release_id}", allow_failure:)
      true
    end

    def delete_tag_ref(tag, allow_failure: false)
      run_gh!("api", "-X", "DELETE", "repos/#{context.release_repo}/git/refs/tags/#{tag}", allow_failure:)
      true
    end

    def create_release(tag, body, title: tag, draft: true, target: nil)
      with_notes_file(body) do |path|
        command = ["release", "create", tag, "--repo", context.release_repo, "--title", title, "--notes-file", path]
        command += ["--target", target] if target
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

    def release_id(tag, allow_failure: false)
      payload = json("gh", "api", "repos/#{context.release_repo}/releases/tags/#{tag}")
      return payload&.fetch("id", nil) if payload
      return nil if allow_failure

      raise Error, "Could not find release for tag #{tag}"
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
