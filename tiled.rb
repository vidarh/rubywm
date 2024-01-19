
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

  # FIXME: Pass this in
  def windows = @desktop.children.find_all{|w| w.mapped && !w.floating?}
  def cleanup = (@root = Node(@root.keep(windows)))
  def find(w) = @root.find(w)

  def apply_placements(window, placements)
    # This only applies placements to *new*
    # placements. That allows windows to be moved around
    # without "snapping back". Consider option to "lock"
    # windows in place?
    placements.each do |leaf|
      p [leaf, window, window.wm_class]
      if !leaf.window && (leaf.iclass == window.wm_class.last || leaf.iclass == window.wm_class.first)
        leaf.window = window
        return true
      end
    end
    false
  end
  
  def place_new(window, placements=[])
    return if apply_placements(window, placements)
    @root.place(window) #if visible(window)
  end

  # Place `window` adjacent to `focus`
  # First finds the leaf `focus` is in,
  # then replaces that leaf with a node.
  # If dir is provided, the node will split in
  # that direction, otherwise it will be the
  # opposite of the parent
  #
  def place_adjacent(window, focus, dir=nil)
    return if apply_placements(window, @root.placements)
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

    # We "fake" this, because calling `place_adjacent`
    # is only called when a map is about to happen,
    # and unless `mapped == true`, the window will be
    # discarded from the layout. This way the window
    # will be resized and moved *before* the map call
    # happens, so as to reduce flicker.
    window.mapped = true

    #  FIXME
    # Having this "callable" is pointless
    # if the interface is broader. This only makes
    # sense if `call` can also receive or get the focus,
    # and a signal of what should be inserted at the focus.
    # I'm not sure if this is "pluggable" enough to be
    # worth trying to handle that.
    call
  end
  
  def call
    new_windows     = windows - @root.children
    cleanup
    placements = @root.placements
    new_windows.each {place_new(_1, placements) }

    children = @root.children
    g = GAP/(1.3**children.length)
    @root.layout(gap(@geom,g), g)
  end
end
