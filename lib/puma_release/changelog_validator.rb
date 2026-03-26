# frozen_string_literal: true

module PumaRelease
  class ChangelogValidator
    CATEGORY_ORDER = {
      "Features" => 1,
      "Bugfixes" => 2,
      "Performance" => 3,
      "Refactor" => 4,
      "Docs" => 5,
      "CI" => 6,
      "Breaking changes" => 7
    }.freeze

    CATEGORY_REGEX = /^\* (#{Regexp.union(CATEGORY_ORDER.keys).source})$/
    ITEM_REGEX = /^  \* .+ \(\[#(\d+)\](, \[#(\d+)\])*\)$/
    INLINE_LINK_REGEX = /\[[^\]]+\]\(/

    def validate(changelog)
      state = :category
      current_category = nil
      last_order = 0
      counts = {categories: 0, items: 0}
      seen = {}
      errors = []

      changelog.each_line(chomp: true).with_index(1) do |raw_line, line_number|
        line = raw_line.delete_suffix("\r")
        handle_line(line, line_number, state, current_category, last_order, counts, seen, errors)
        state, current_category, last_order = transition(line, state, current_category, last_order, seen)
      end

      errors << "Line #{changelog.lines.count}: category '* #{current_category}' must contain at least one item." if state == :item
      errors << "Changelog must contain at least one category." if counts.fetch(:categories).zero?
      errors << "Changelog must contain at least one changelog item." if counts.fetch(:items).zero?
      errors
    end

    private

    def handle_line(line, line_number, state, current_category, last_order, counts, seen, errors)
      if line.empty?
        errors << "Line #{line_number}: category '* #{current_category}' must contain at least one item." if state == :item
        return
      end
      return errors << "Line #{line_number}: headings are not allowed in the changelog body." if line.start_with?("#")
      return handle_category(line, line_number, state, current_category, last_order, counts, seen, errors) if line.match?(CATEGORY_REGEX)

      errors << "Line #{line_number}: inline markdown links are not allowed; use reference-style PR refs like ([#123])." if line.match?(INLINE_LINK_REGEX)
      return handle_item(line, line_number, state, counts, errors) if line.match?(ITEM_REGEX)

      errors << if line.start_with?("*")
        "Line #{line_number}: unsupported category. Allowed categories: #{CATEGORY_ORDER.keys.join(", ")}."
      else
        "Line #{line_number}: unexpected content. Expected a category heading or an item like '  * Description ([#123])'."
      end
    end

    def handle_category(line, line_number, state, current_category, last_order, counts, seen, errors)
      category = line.match(CATEGORY_REGEX)[1]
      order = CATEGORY_ORDER.fetch(category)
      errors << "Line #{line_number}: category '* #{current_category}' must contain at least one item before the next category." if state == :item
      errors << "Line #{line_number}: blank line required between categories." if state == :item_or_blank
      errors << "Line #{line_number}: categories must appear in this order: #{CATEGORY_ORDER.keys.join(", ")}." if order < last_order
      errors << "Line #{line_number}: duplicate category '* #{category}'." if seen[category]
      counts[:categories] += 1
    end

    def handle_item(line, line_number, state, counts, errors)
      errors << "Line #{line_number}: changelog items must appear under a category heading." unless %i[item item_or_blank].include?(state)
      counts[:items] += 1
    end

    def transition(line, state, current_category, last_order, seen)
      return [:category, current_category, last_order] if line.empty? && %i[item item_or_blank].include?(state)
      return [state, current_category, last_order] if line.empty? || line.start_with?("#")
      return [:item_or_blank, current_category, last_order] if line.match?(ITEM_REGEX)
      return [state, current_category, last_order] unless (match = line.match(CATEGORY_REGEX))

      current_category = match[1]
      seen[current_category] = true
      [:item, current_category, CATEGORY_ORDER.fetch(current_category)]
    end
  end
end
