require "minitest/autorun"
require_relative "../../leaf"
require_relative "../../node"

# Structural behaviour of the layout tree (no geometry / no X server).
# Windows are represented by plain symbols — Leaf just stores them.
class TestNode < Minitest::Test
  def test_swapdir
    assert_equal :tb, Node.swapdir(:lr)
    assert_equal :lr, Node.swapdir(:tb)
    assert_nil Node.swapdir(:nope)
  end

  def test_place_appends_then_splits
    n = Node.new
    n.place(:a)
    assert_equal [:a], n.children
    n.place(:b)
    assert_equal [:a, :b], n.children
    assert_equal 2, n.nodes.length

    # third window splits the second slot into a sub-node
    n.place(:c)
    assert_equal [:a, :b, :c], n.children
    assert_equal 2, n.nodes.length
    assert_instance_of Node, n.nodes[1]

    # fourth keeps descending the right spine
    n.place(:d)
    assert_equal [:a, :b, :c, :d], n.children
  end

  def test_keep_drops_missing_windowless_leaves
    n = Node.new
    [:a, :b, :c].each { |w| n.place(w) }
    kept = Node(n.keep([:a, :c]))   # :b no longer present, has no iclass -> dropped
    assert_equal [:a, :c], kept.children
  end

  def test_keep_collapses_single_child_to_leaf
    n = Node.new
    [:a, :b].each { |w| n.place(w) }
    kept = n.keep([:a])             # only :a survives -> collapses to the leaf
    assert_instance_of Leaf, kept
    assert_equal :a, kept.window
  end

  def test_find_locates_leaf_for_window
    n = Node.new
    [:a, :b].each { |w| n.place(w) }
    leaf = n.find(:b)
    assert_instance_of Leaf, leaf
    assert_equal :b, leaf.window
    assert_nil n.find(:missing)
  end

  def test_place_adjacent_creates_subnode_with_direction
    n = Node.new(dir: :lr)
    [:a, :b].each { |w| n.place(w) }
    focus_leaf = n.find(:a)
    n.place_adjacent(:x, focus_leaf, :tb)
    assert_includes n.children, :x
    sub = n.nodes.find { |nd| nd.is_a?(Node) }
    assert_equal :tb, sub.dir
  end
end
