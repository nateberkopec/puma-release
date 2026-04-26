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

  def test_parse_sets_forced_release_version
    options = PumaRelease::Options.parse(["--release-version", "7.3.0"])

    assert_equal "7.3.0", options.fetch(:forced_version)
  end
end
