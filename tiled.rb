
GAP = 64
# Outer gap shrinks as a desktop gains windows, so a busy desktop wastes less
# edge space. Each additional top-level window divides the gap by this factor.
GAP_DECAY = 1.3

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

  def update_geometry(geom = nil)
    # Tile within the desktop's work area (monitor minus dock struts); fall back
    # to whatever geometry we were handed if the desktop has no monitor yet.
    @geom = (@desktop.work_area || geom).dup
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
    g = GAP/(GAP_DECAY ** @root.children.length)
    @root.layout(gap(@geom,g), g)
  end
  
  def call(focus=nil)
    current_geom = @desktop.work_area
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
