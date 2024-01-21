
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

  def apply_placements(window) = @root.placements.any? { _1.accept(window) }
  
  def place(window, focus=nil, dir=nil)
    return if apply_placements(window)
    return @root.place(window) if !focus
    leaf = self.find(focus)
    leaf&.parent&.place_adjacent(window, leaf, dir) || @root.place(window)
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
