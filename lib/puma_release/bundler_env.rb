# frozen_string_literal: true

module PumaRelease
  module BundlerEnv
    NIL_SENTINEL = "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"
    CONTROL_KEYS = %w[
      BUNDLE_BIN_PATH
      BUNDLE_GEMFILE
      BUNDLE_LOCKFILE
      BUNDLER_SETUP
      BUNDLER_VERSION
    ].freeze

    module_function

    def clean(source)
      source.dup.tap do |env|
        env.keys.grep(/\ABUNDLER_ORIG_/).each { |key| restore_original!(env, key) }
        CONTROL_KEYS.each { |key| env[key] = nil }
      end
    end

    def restore_original!(env, bundler_key)
      original_key = bundler_key.delete_prefix("BUNDLER_ORIG_")
      original_value = env[bundler_key]
      env[bundler_key] = nil
      env[original_key] = (original_value == NIL_SENTINEL) ? nil : original_value
    end
  end
end
