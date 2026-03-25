# frozen_string_literal: true

require_relative "../test_helper"

class RunTest < Minitest::Test
  class FakeUI
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(message)
      infos << message
    end
  end

  def test_returns_complete_without_prompt_when_release_is_already_complete
    ui = FakeUI.new
    context = OpenStruct.new(ui:)
    run = PumaRelease::Commands::Run.allocate
    run.instance_variable_set(:@context, context)

    detector = Object.new
    def detector.next_step = :complete
    run.define_singleton_method(:stage_detector) { detector }
    run.define_singleton_method(:confirm_step) { flunk "confirm_step should not be called for a complete release" }

    assert_equal :complete, run.call
    assert_equal ["The current release is already complete. No action needed."], ui.infos
  end
end
