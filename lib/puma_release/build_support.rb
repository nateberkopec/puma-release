# frozen_string_literal: true

module PumaRelease
  class BuildSupport
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def build_jruby_gem(version)
      return build_with_mise(version) if context.shell.available?("mise")
      return build_with_local_jruby(version) if context.shell.available?("jruby")

      false
    end

    private

    def build_with_mise(version)
      jruby_version = latest_jruby_version
      return build_with_local_jruby(version) if jruby_version.nil? && context.shell.available?("jruby")
      return false if jruby_version.nil?

      context.ui.info("Building JRuby gem with mise and ruby@#{jruby_version}...")
      context.shell.run("mise", "exec", "ruby@#{jruby_version}", "--", "bundle", "exec", "rake", "java", "gem")
      context.ui.info("Built: pkg/puma-#{version}-java.gem")
      true
    end

    def build_with_local_jruby(version)
      context.ui.info("Building JRuby gem with local jruby...")
      context.shell.run("jruby", "-S", "bundle", "exec", "rake", "java", "gem")
      context.ui.info("Built: pkg/puma-#{version}-java.gem")
      true
    end

    def latest_jruby_version
      result = context.shell.run("mise", "latest", "ruby@jruby", allow_failure: true)
      return result.stdout.strip if result.success? && !result.stdout.strip.empty?

      context.ui.warn("mise could not determine a JRuby version via ruby@jruby.")
      nil
    end
  end
end
