require "minitest/autorun"
require "bundler/setup"
require "X11"
require_relative "../../geom"

# Pure geometry helpers used by the tiling layout. No X server needed —
# these operate on X11::Form::Geometry structs.
class TestGeom < Minitest::Test
  def geom(x, y, w, h)
    X11::Form::Geometry.new.tap { |g| g.x = x; g.y = y; g.width = w; g.height = h }
  end

  def test_gap_insets_on_all_sides
    g = gap(geom(0, 0, 1000, 800), 10)
    assert_equal 10,  g.x
    assert_equal 10,  g.y
    assert_equal 980, g.width   # 1000 - 2*10
    assert_equal 780, g.height  # 800  - 2*10
  end

  def test_gap_does_not_mutate_input
    src = geom(0, 0, 1000, 800)
    gap(src, 10)
    assert_equal 1000, src.width
    assert_equal 0, src.x
  end

  def test_split_lr_halves_width
    a = split_geom(geom(0, 0, 1000, 800), :lr, 0, 0, 0.5)
    b = split_geom(geom(0, 0, 1000, 800), :lr, 1, 0, 0.5)
    assert_in_delta 500, a.width, 0.001
    assert_in_delta 500, b.width, 0.001
    assert_in_delta 0,   a.x,     0.001
    assert_in_delta 500, b.x,     0.001
    assert_equal 800, a.height
  end

  def test_split_lr_respects_ratio_and_gap
    a = split_geom(geom(0, 0, 1000, 800), :lr, 0, 100, 0.25)
    b = split_geom(geom(0, 0, 1000, 800), :lr, 1, 100, 0.25)
    # usable width after gap = 900; left = 225, right = 675, right.x = 225 + 100
    assert_in_delta 225, a.width, 0.001
    assert_in_delta 675, b.width, 0.001
    assert_in_delta 325, b.x,     0.001
  end

  def test_split_tb_halves_height
    a = split_geom(geom(0, 0, 1000, 800), :tb, 0, 0, 0.5)
    b = split_geom(geom(0, 0, 1000, 800), :tb, 1, 0, 0.5)
    assert_in_delta 400, a.height, 0.001
    assert_in_delta 400, b.height, 0.001
    assert_in_delta 400, b.y,      0.001
    assert_equal 1000, a.width
  end

  def test_split_unknown_direction_raises
    assert_raises(RuntimeError) { split_geom(geom(0, 0, 10, 10), :diagonal, 0, 0, 0.5) }
  end
end
