# frozen_string_literal: true

require "date"

module PumaRelease
  class RepoFiles
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def current_version
      content[/PUMA_VERSION = VERSION = "([^"]+)"/, 1] || raise(Error, "Could not read current version")
    end

    def current_code_name
      content[/CODE_NAME = "([^"]+)"/, 1] || raise(Error, "Could not read current code name")
    end

    def release_name(version)
      return "v#{version}" unless codename_applicable?(version)

      "v#{version} - #{current_code_name}"
    end

    def update_security!(new_version)
      major = new_version.split(".").first.to_i
      new_majors = [major, major - 1]
      i = -1
      updated = context.security_file.read.gsub(/Latest release in \d+\.x/) do
        i += 1
        i < new_majors.size ? "Latest release in #{new_majors[i]}.x" : $&
      end
      context.security_file.write(updated)
    end

    def update_version!(new_version, bump_type, codename: nil)
      updated = content.sub(/PUMA_VERSION = VERSION = ".*"/, "PUMA_VERSION = VERSION = \"#{new_version}\"")
      unless bump_type == "patch"
        placeholder = codename || "INSERT CODENAME HERE"
        updated = updated.sub(/CODE_NAME = ".*"/, "CODE_NAME = \"#{placeholder}\"")
      end
      context.version_file.write(updated)
    end

    def extract_history_section(version)
      lines = context.history_file.readlines(chomp: true)
      start = lines.index { |line| line.match?(/^## #{Regexp.escape(version)} /) }
      return nil unless start

      lines[(start + 1)..].take_while { |line| !line.start_with?("## ") }.join("\n").strip
    end

    def prepend_history_section!(version, changelog, refs)
      header = "## #{version} / #{Date.today.strftime("%Y-%m-%d")}"
      body = [header, changelog.strip, context.history_file.read].join("\n\n")
      context.history_file.write(body)
      insert_link_refs!(refs)
    end

    def insert_link_refs!(refs)
      return if refs.empty?

      lines = context.history_file.readlines(chomp: true)
      index = lines.index { |line| line.match?(/^\[#\d+\]:/) }
      updated = if index
        [*lines[0...index], *refs.lines(chomp: true), *lines[index..]].join("\n")
      else
        [context.history_file.read.rstrip, refs].join("\n")
      end
      context.history_file.write("#{updated}\n")
    end

    private

    def codename_applicable?(version)
      version.split(".").last == "0"
    end

    def content
      context.version_file.read
    end
  end
end
