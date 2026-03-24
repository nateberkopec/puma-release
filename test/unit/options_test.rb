# frozen_string_literal: true

require_relative "../test_helper"

class OptionsTest < Minitest::Test
  def test_parse_sets_live_flag
    options = PumaRelease::Options.parse(["--live"])

    assert_equal true, options.fetch(:live)
  end

  def test_parse_sets_skip_ci_check_flag
    options = PumaRelease::Options.parse(["--skip-ci-check"])

    assert_equal true, options.fetch(:skip_ci_check)
  end
end
