require "minitest/autorun"
require_relative "../../options"

# CLI flag parsing. Regression guard: the old inline parser used two
# consecutive ARGV.shift calls, so `--debug` alone never took effect.
class TestOptions < Minitest::Test
  def test_no_flags
    o = Options.parse([])
    refute o[:drb]
    refute o[:debug]
  end

  def test_drb_only
    o = Options.parse(["--drb"])
    assert o[:drb]
    refute o[:debug]
  end

  def test_debug_only
    o = Options.parse(["--debug"])
    assert o[:debug]
    refute o[:drb]
  end

  def test_both_in_either_order
    assert Options.parse(["--debug", "--drb"]).values_at(:drb, :debug).all?
    assert Options.parse(["--drb", "--debug"]).values_at(:drb, :debug).all?
  end

  def test_unknown_flag_raises
    assert_raises(ArgumentError) { Options.parse(["--nope"]) }
  end
end
