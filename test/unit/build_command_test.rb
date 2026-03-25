# frozen_string_literal: true

require_relative "../test_helper"

class BuildCommandTest < Minitest::Test
  class FakeUI
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message)
      warnings << message
    end
  end

  def test_replaces_a_draft_release_tag_even_when_it_already_points_at_head
    shell = FakeShell.new
    ui = FakeUI.new
    confirmations = []
    context = OpenStruct.new(shell:, ui:, release_repo: "puma/puma")
    context.define_singleton_method(:confirm_live_gh_command!) { |*command| confirmations << command }

    local_tag_created = false
    git_repo = Object.new
    git_repo.define_singleton_method(:head_sha) { "abc123" }
    git_repo.define_singleton_method(:remote_tag_sha) { |_tag| "abc123" }
    git_repo.define_singleton_method(:remote_tag_object_sha) { |_tag| "remote-tag-object" }
    git_repo.define_singleton_method(:local_tag_sha) { |_tag| local_tag_created ? "abc123" : "" }
    git_repo.define_singleton_method(:local_tag_signed?) { |_tag| local_tag_created }
    git_repo.define_singleton_method(:local_tag_object_sha) { |_tag| local_tag_created ? "local-tag-object" : "" }
    git_repo.define_singleton_method(:create_signed_tag!) { |_tag| local_tag_created = true }

    github = Object.new
    github.define_singleton_method(:release) { |_tag| { "isDraft" => true } }

    command = PumaRelease::Commands::Build.allocate
    command.instance_variable_set(:@context, context)
    command.instance_variable_set(:@git_repo, git_repo)
    command.instance_variable_set(:@github, github)

    command.send(:retarget_draft_release_tag_if_needed, "v7.2.0")

    assert_includes ui.warnings, "Replacing draft release tag v7.2.0 with the local signed tag..."
    assert_equal [["gh", "api", "-X", "DELETE", "repos/puma/puma/git/refs/tags/v7.2.0"]], confirmations
    assert_includes shell.commands, ["gh", "api", "-X", "DELETE", "repos/puma/puma/git/refs/tags/v7.2.0"]
  end
end
