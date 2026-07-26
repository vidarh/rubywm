require "minitest/autorun"
require "open3"
require "tmpdir"

class TestRwmctlBootstrap < Minitest::Test
  SCRIPT = File.expand_path("../../rwmctl.rb", __dir__)

  def with_foreign_project
    Dir.mktmpdir("rwmctl-foreign-bundle") do |dir|
      File.write(
        File.join(dir, "Gemfile"),
        "source \"https://rubygems.org\"\n",
      )
      yield dir
    end
  end

  def assert_uses_own_bundle(env, dir)
    _stdout, stderr, status = Open3.capture3(
      env,
      SCRIPT,
      "not-a-command",
      chdir: dir,
    )

    refute status.success?
    assert_includes stderr, "usage:"
    refute_includes stderr, "cannot load such file -- X11"
  end

  def test_ignores_a_gemfile_in_the_current_directory
    with_foreign_project do |dir|
      assert_uses_own_bundle({}, dir)
    end
  end

  def test_escapes_a_preloaded_foreign_bundle
    with_foreign_project do |dir|
      assert_uses_own_bundle(
        {
          "BUNDLE_GEMFILE" => File.join(dir, "Gemfile"),
          "RUBYOPT" => "-rbundler/setup",
        },
        dir,
      )
    end
  end
end
