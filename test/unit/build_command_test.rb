# frozen_string_literal: true

require_relative "../test_helper"

class BuildCommandTest < Minitest::Test
  def test_sync_release_target_to_tag_is_a_no_op_when_release_is_missing
    git_repo = Object.new
    git_repo.define_singleton_method(:local_tag_sha) { |_tag| "abc123" }

    github = Object.new
    calls = []
    github.define_singleton_method(:release) { |_tag| nil }
    github.define_singleton_method(:edit_release_target) { |_tag, _sha| calls << :edit_release_target }

    command = PumaRelease::Commands::Build.allocate
    command.instance_variable_set(:@git_repo, git_repo)
    command.instance_variable_set(:@github, github)

    command.send(:sync_release_target_to_tag, "v7.2.0")

    assert_empty calls
  end
end
