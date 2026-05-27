# frozen_string_literal: true

require "tmpdir"

module PumaRelease
  module TemporaryBundleLockfile
    module_function

    def with_env
      Dir.mktmpdir("puma-release-bundle-lock") do |dir|
        yield({"BUNDLE_LOCKFILE" => File.join(dir, "Gemfile.lock")})
      end
    end
  end
end
