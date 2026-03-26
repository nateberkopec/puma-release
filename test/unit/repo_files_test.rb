# frozen_string_literal: true

require_relative "../test_helper"

class RepoFilesTest < Minitest::Test
  def test_current_version_reads_puma_const
    temp_repo do |repo|
      repo.join("lib/puma/const.rb").write("PUMA_VERSION = VERSION = \"7.2.0\"\nCODE_NAME = \"On The Corner\"\n")
      repo.join("History.md").write("## 7.2.0 / 2026-01-20\n\n* Bugfixes\n  * One thing ([#1])\n")
      context = OpenStruct.new(version_file: repo.join("lib/puma/const.rb"), history_file: repo.join("History.md"))

      assert_equal "7.2.0", PumaRelease::RepoFiles.new(context).current_version
    end
  end

  def test_update_version_replaces_codename_for_minor_release
    temp_repo do |repo|
      repo.join("lib/puma/const.rb").write("PUMA_VERSION = VERSION = \"7.2.0\"\nCODE_NAME = \"On The Corner\"\n")
      repo.join("History.md").write("")
      context = OpenStruct.new(version_file: repo.join("lib/puma/const.rb"), history_file: repo.join("History.md"))

      PumaRelease::RepoFiles.new(context).update_version!("7.3.0", "minor")

      content = repo.join("lib/puma/const.rb").read
      assert_includes content, 'PUMA_VERSION = VERSION = "7.3.0"'
      assert_includes content, 'CODE_NAME = "INSERT CODENAME HERE"'
    end
  end

  def test_release_name_includes_codename_for_dot_zero_releases
    temp_repo do |repo|
      repo.join("lib/puma/const.rb").write("PUMA_VERSION = VERSION = \"7.3.0\"\nCODE_NAME = \"Shiny New Codename\"\n")
      repo.join("History.md").write("")
      context = OpenStruct.new(version_file: repo.join("lib/puma/const.rb"), history_file: repo.join("History.md"))

      assert_equal "v7.3.0 - Shiny New Codename", PumaRelease::RepoFiles.new(context).release_name("7.3.0")
    end
  end

  def test_release_name_omits_codename_for_patch_releases
    temp_repo do |repo|
      repo.join("lib/puma/const.rb").write("PUMA_VERSION = VERSION = \"7.3.1\"\nCODE_NAME = \"Shiny New Codename\"\n")
      repo.join("History.md").write("")
      context = OpenStruct.new(version_file: repo.join("lib/puma/const.rb"), history_file: repo.join("History.md"))

      assert_equal "v7.3.1", PumaRelease::RepoFiles.new(context).release_name("7.3.1")
    end
  end

  def test_update_security_updates_supported_versions_for_major_release
    temp_repo do |repo|
      repo.join("SECURITY.md").write(<<~MD)
        # Security Policy

        ## Supported Versions

        | Version       | Supported  |
        | :------------ | :--------: |
        | Latest release in 7.x | ✅ |
        | Latest release in 6.x | ✅ |
        | All other releases    | ❌ |

        ## Reporting a Vulnerability

        Contact [Evan Phoenix.](https://github.com/evanphx)
      MD
      context = OpenStruct.new(security_file: repo.join("SECURITY.md"))

      PumaRelease::RepoFiles.new(context).update_security!("8.0.0")

      content = repo.join("SECURITY.md").read
      assert_includes content, "Latest release in 8.x"
      assert_includes content, "Latest release in 7.x"
      refute_includes content, "Latest release in 6.x"
    end
  end

  def test_update_security_preserves_rest_of_file
    temp_repo do |repo|
      repo.join("SECURITY.md").write(<<~MD)
        # Security Policy

        ## Supported Versions

        | Version       | Supported  |
        | :------------ | :--------: |
        | Latest release in 7.x | ✅ |
        | Latest release in 6.x | ✅ |
        | All other releases    | ❌ |

        ## Reporting a Vulnerability

        Contact [Evan Phoenix.](https://github.com/evanphx)
      MD
      context = OpenStruct.new(security_file: repo.join("SECURITY.md"))

      PumaRelease::RepoFiles.new(context).update_security!("8.0.0")

      content = repo.join("SECURITY.md").read
      assert_includes content, "# Security Policy"
      assert_includes content, "All other releases"
      assert_includes content, "Contact [Evan Phoenix.](https://github.com/evanphx)"
    end
  end

  def test_prepend_history_section_inserts_new_entry_and_refs
    temp_repo do |repo|
      repo.join("lib/puma/const.rb").write("PUMA_VERSION = VERSION = \"7.2.0\"\n")
      repo.join("History.md").write("## 7.2.0 / 2026-01-20\n\n* Bugfixes\n  * Existing ([#1])\n\n[#1]:https://example.test/1\n")
      context = OpenStruct.new(version_file: repo.join("lib/puma/const.rb"), history_file: repo.join("History.md"))

      PumaRelease::RepoFiles.new(context).prepend_history_section!("7.2.1", "* Bugfixes\n  * New fix ([#2])", "[#2]:https://example.test/2")

      updated = repo.join("History.md").read
      assert_includes updated, "## 7.2.1 / #{Date.today.strftime("%Y-%m-%d")}"
      assert_match(/\[#2\]:https:\/\/example\.test\/2\n\[#1\]:https:\/\/example\.test\/1/, updated)
    end
  end
end
