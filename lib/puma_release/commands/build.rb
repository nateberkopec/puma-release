# frozen_string_literal: true

module PumaRelease
  module Commands
    class Build
      attr_reader :context, :git_repo, :repo_files

      def initialize(context)
        @context = context
        @git_repo = GitRepo.new(context)
        @repo_files = RepoFiles.new(context)
      end

      def call
        context.check_dependencies!("git", "bundle")
        context.announce_live_mode!
        context.ensure_release_writes_allowed!
        git_repo.ensure_clean_base!
        version = repo_files.current_version
        tag = git_repo.release_tag(version)
        context.ui.info("Ensuring tag #{tag} points at HEAD and is pushed...")
        git_repo.ensure_release_tag_pushed!(tag)
        context.ui.info("Building MRI gem...")
        context.shell.run("bundle", "exec", "rake", "build")
        context.ui.info("Built: pkg/puma-#{version}.gem")
        jruby_built = BuildSupport.new(context).build_jruby_gem(version)
        manual_jruby_instructions unless jruby_built
        context.events.publish(:checkpoint, kind: :wait_for_rubygems, version:, tag:)
        context.ui.info("STOP: push both gems to RubyGems, then rerun puma-release.")
        :wait_for_rubygems
      end

      private

      def manual_jruby_instructions
        context.ui.warn("JRuby gem was not built automatically.")
        puts "To build it manually, switch to JRuby and run:"
        puts "  bundle exec rake java gem"
      end
    end
  end
end
