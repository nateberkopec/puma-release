# frozen_string_literal: true

require "json"
require "open3"
require_relative "../test_helper"

class ForkSmokeTest < Minitest::Test
  def test_runs_against_the_fork_when_enabled
    skip "set PUMA_RELEASE_SMOKE=1 to run" unless ENV["PUMA_RELEASE_SMOKE"] == "1"

    Dir.mktmpdir do |dir|
      repo = Pathname(dir).join("puma")
      release_repo = ENV.fetch("PUMA_RELEASE_SMOKE_REPO", "nateberkopec/puma")
      clone_repo(repo, release_repo)
      install_bundle(repo)

      run_cli(repo, release_repo, "run")
      pr = JSON.parse(run_command("gh", "pr", "list", "--repo", release_repo, "--state", "open", "--search", "head:#{release_repo.split('/').first}:release-v", "--json", "url,number,headRefName").first)
      refute_empty pr

      run_command("gh", "pr", "merge", pr.fetch(0).fetch("url"), "--merge", "--admin")
      run_command("git", "checkout", "main", chdir: repo.to_s)
      run_command("git", "pull", "--ff-only", chdir: repo.to_s)
      run_cli(repo, release_repo, "run")
      run_cli(repo, release_repo, "run")
    end
  end

  private

  def clone_repo(path, release_repo)
    run_command("git", "clone", "https://github.com/#{release_repo}.git", path.to_s)
    run_command("git", "config", "user.name", "Puma Release Smoke", chdir: path.to_s)
    run_command("git", "config", "user.email", "smoke@example.test", chdir: path.to_s)
  end

  def install_bundle(path)
    run_command("bundle", "install", chdir: path.to_s)
  end

  def run_cli(path, release_repo, command)
    env = {
      "AGENT_CMD" => ENV.fetch("PUMA_RELEASE_SMOKE_AGENT_CMD", "/Users/nateberkopec/.local/share/mise/installs/npm-mariozechner-pi-coding-agent/0.62.0/bin/pi"),
      "PUMA_RELEASE_CHANGELOG_BACKEND" => "agent",
      "PUMA_RELEASE_JRUBY_BUILD_COMMAND" => "jruby -S bundle exec rake java gem"
    }
    run_command(
      Gem.ruby, File.expand_path("../../../exe/puma-release", __dir__),
      "--repo-dir", path.to_s,
      "--release-repo", release_repo,
      "--metadata-repo", "puma/puma",
      "--allow-unknown-ci",
      "-y",
      command,
      env:
    )
  end

  def run_command(*command, chdir: Dir.pwd, env: {})
    stdout, stderr, status = Open3.capture3(ENV.to_h.merge(env), *command, chdir:)
    raise "#{command.join(' ')} failed\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}" unless status.success?

    [stdout, stderr]
  end
end
