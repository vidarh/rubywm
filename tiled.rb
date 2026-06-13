
GAP = 64

require_relative 'geom.rb'
require_relative 'leaf.rb'
require_relative 'node.rb'
require_relative 'layout'

class TiledLayout < Layout
  attr_reader :root
  
  def initialize(desktop, geom)
    @desktop = desktop
    update_geometry(geom)
    @root = Node.new(dir: :lr)
  end

  def update_geometry(geom)
    # FIXME: Only do this if geom is actually different from @geom

    @geom = geom.dup
    # FIXME: This is to account for a bar, but we shouldn't just assume
    # the height here
    @geom.height -= 30

    relayout if @root&.children&.any?
  end

  def find(w) = @root.find(w)

  def place(window, focus=nil, dir=nil)
    return if apply_placements(window)
    return @root.place(window) if !focus
    leaf = self.find(focus)
    if leaf && leaf.parent
      leaf.parent.place_adjacent(window, leaf, dir)
    else @root.place(window)
    end
    call
    true
  end

  def relayout
    g = GAP/(1.3 ** @root.children.length)
    @root.layout(gap(@geom,g), g)
  end
  
  def call(focus=nil)
    current_geom = @desktop.geometry
    if @geom.width != current_geom.width || @geom.height != current_geom.height
      update_geometry(current_geom)
    end

    new_windows = windows - @root.children
    cleanup
    new_windows.each { place(_1,focus) }
    relayout
  end

  def windows = @desktop.children.find_all{|w| w.mapped && !w.floating?}
  def cleanup = (@root = Node(@root.keep(windows)))
  def apply_placements(window) = @root.placements.any? { _1.accept(window) }
  
  # Explicitly remove a window from the layout
  # This is useful when moving a window to another desktop/monitor
  def remove_window(window)
    leaf = find(window)
    if leaf
      leaf.window = nil
      cleanup
      relayout
      true
    else
      false
    end
  end
end
