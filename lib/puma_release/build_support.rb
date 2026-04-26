# frozen_string_literal: true

module PumaRelease
  class BuildSupport
    MISE_JRUBY_JAVA_RUNTIME = "java@21"

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

      jruby_runtime = "ruby@#{jruby_version}"
      ensure_mise_runtime_installed!(jruby_runtime)
      context.ui.info("Ensuring JRuby bundle is installed with mise, #{MISE_JRUBY_JAVA_RUNTIME}, and #{jruby_runtime}...")
      ensure_bundle_installed!("mise", "exec", MISE_JRUBY_JAVA_RUNTIME, jruby_runtime, "--", "bundle")
      context.ui.info("Building JRuby gem with mise, #{MISE_JRUBY_JAVA_RUNTIME}, and #{jruby_runtime}...")
      context.shell.run("mise", "exec", MISE_JRUBY_JAVA_RUNTIME, jruby_runtime, "--", "bundle", "exec", "rake", "java", "gem")
      context.ui.info("Built: pkg/puma-#{version}-java.gem")
      true
    end

    def ensure_mise_runtime_installed!(jruby_runtime)
      context.ui.info("Ensuring #{MISE_JRUBY_JAVA_RUNTIME} is installed for JRuby...")
      context.shell.run("mise", "install", MISE_JRUBY_JAVA_RUNTIME)
      java_home = context.shell.output("mise", "where", MISE_JRUBY_JAVA_RUNTIME).strip
      context.ui.info("Ensuring #{jruby_runtime} is installed with #{MISE_JRUBY_JAVA_RUNTIME}...")
      context.shell.run("mise", "install", jruby_runtime, env_overrides: java_env_overrides(java_home))
    end

    def java_env_overrides(java_home)
      path = [File.join(java_home, "bin"), shell_path].reject(&:empty?).join(File::PATH_SEPARATOR)
      {"JAVA_HOME" => java_home, "PATH" => path}
    end

    def shell_path
      return context.shell.env.fetch("PATH", "") if context.shell.respond_to?(:env)

      ENV.fetch("PATH", "")
    end

    def build_with_local_jruby(version)
      context.ui.info("Ensuring JRuby bundle is installed with local jruby...")
      ensure_bundle_installed!("jruby", "-S", "bundle")
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

    def ensure_bundle_installed!(*bundle_command)
      check = context.shell.run(*bundle_command, "check", allow_failure: true)
      return if check.success?

      context.shell.run(*bundle_command, "install")
    end
  end
end
