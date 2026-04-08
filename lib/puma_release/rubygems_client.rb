# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module PumaRelease
  class RubyGemsClient
    GEM_NAME = "puma"

    def initialize(_context)
    end

    def release_published?(version)
      platforms = versions_for(version).map { |item| item.fetch("platform", "ruby") }
      %w[ruby java].all? { |platform| platforms.include?(platform) }
    end

    private

    def versions_for(version)
      all_versions.select { |item| item.fetch("number") == version }
    end

    def all_versions
      @all_versions ||= begin
        response = Net::HTTP.get_response(URI("https://rubygems.org/api/v1/versions/#{GEM_NAME}.json"))
        raise Error, "Could not fetch versions for #{GEM_NAME} from RubyGems" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
