
GAP = 64

require_relative 'geom.rb'
require_relative 'leaf.rb'
require_relative 'node.rb'

class TiledLayout
  attr_reader :root
  
  def initialize(desktop, geom)
    @desktop = desktop
    @geom = geom.dup
    # FIXME: This is to account for a bar, but we shouldn't just assume
    # the height here
    @geom.height -= 30
    @root = Node.new(dir: :lr)
  end

  def windows = @desktop.children.find_all{|w| w.mapped && !w.floating?}
  def cleanup = (@root = Node(@root.keep(windows)))
  def find(w) = @root.find(w)

  def apply_placements(window)
    @root.placements.each do |leaf|
      if !leaf.window &&
        (leaf.iclass == window.wm_class.last ||
         leaf.iclass == window.wm_class.first)
        leaf.window = window
        return true
      end
    end
    false
  end
  
  def place(window, focus=nil, dir=nil)
    return if apply_placements(window)
    return @root.place(window) if !focus
    leaf = self.find(focus)
    return @root.place(window) if !leaf
    node = leaf.parent
    l = Leaf.new(window)
    # FIXME: Move this to Node class.
    if node.nodes.length == 2
      i = node.nodes.index(leaf)
      dir ||= Node.swapdir(node.dir)
      new_node = Node.new([leaf, l], parent: node, dir: dir)
      l.parent = new_node
      node.nodes[i] = new_node
    else
      l.parent = node
      node.dir = dir if dir
      node.nodes << l
    end
    call
  end
  
  def call
    new_windows = windows - @root.children
    cleanup
    new_windows.each { place(_1) }

    g = GAP/(1.3 ** @root.children.length)
    @root.layout(gap(@geom,g), g)
  end
end
