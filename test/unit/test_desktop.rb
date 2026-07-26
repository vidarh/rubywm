require "minitest/autorun"
require "bundler/setup"
require "X11"
require_relative "../../desktop"

class TestDesktop < Minitest::Test
  FakeWM = Struct.new(:monitors, :windows, :rootgeom)

  def setup
    @wm = FakeWM.new([], {}, nil)
  end

  def test_stable_metadata_and_mode_code
    desktop = Desktop.new(
      @wm, 10, "RubyWM",
      key: "project:rubywm",
      project: "/src/rubywm",
      group: "Coding",
      mode: :floating,
    )

    assert_equal "project:rubywm", desktop.key
    assert_equal "/src/rubywm", desktop.project
    assert_equal "Coding", desktop.group
    assert_equal 1, desktop.mode_code
  end

  def test_default_key_is_deterministic
    assert_equal "desktop-3", Desktop.new(@wm, 2, "3").key
  end

  def test_flags_are_independent
    flags = Desktop::FLAG_STATIC |
            Desktop::FLAG_DESKTOP_WINDOW |
            Desktop::FLAG_SLOT_BACKED |
            Desktop::FLAG_AVAILABLE
    desktop = Desktop.new(@wm, 0, "Workbench", flags: flags)

    assert desktop.static?
    refute desktop.pinned?
    assert desktop.desktop_window?
    assert desktop.slot_backed?
    assert desktop.available_placeholder?
    refute desktop.group_root?
  end
end
