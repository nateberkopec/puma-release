# frozen_string_literal: true

require_relative "../test_helper"

class ChangelogValidatorTest < Minitest::Test
  def test_valid_changelog_has_no_errors
    changelog = <<~CHANGELOG
      * Features
        * Add a nice thing ([#10])

      * Bugfixes
        * Fix a rough edge ([#11], [#12])
    CHANGELOG

    assert_empty PumaRelease::ChangelogValidator.new.validate(changelog)
  end

  def test_rejects_inline_links
    changelog = <<~CHANGELOG
      * Features
        * Add a nice thing [#10](https://example.test)
    CHANGELOG

    errors = PumaRelease::ChangelogValidator.new.validate(changelog)

    assert_includes errors.join("\n"), "inline markdown links are not allowed"
  end

  def test_rejects_out_of_order_categories
    changelog = <<~CHANGELOG
      * Docs
        * Update docs ([#10])

      * Features
        * Add a nice thing ([#11])
    CHANGELOG

    errors = PumaRelease::ChangelogValidator.new.validate(changelog)

    assert_includes errors.join("\n"), "categories must appear in this order"
  end
end
