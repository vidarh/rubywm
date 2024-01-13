
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

  def place_new(window, placements)
    # This only applies placements to *new*
    # placements. That allows windows to be moved around
    # without "snapping back". Consider option to "lock"
    # windows in place?
    placements.each do |leaf|
      p [leaf, window, window.wm_class]
      if !leaf.window && (leaf.iclass == window.wm_class.last || leaf.iclass == window.wm_class.first)
        leaf.window = window
        p [:set_leaf, leaf]
        return
      end
    end
    @root.place(window) #if visible(window)
  end
  
  def call
    new_windows     = windows - @root.children
    cleanup

    placements = @root.placements
    p [:PLACEMENTS, placements]

    new_windows.each {|window|
      place_new(window, placements)
    }
    @windows = @root.children
    g = GAP/(1.3**@windows.length)
    @root.layout(gap(@geom,g), g)
    pp @root
    pp @windows.length
  end
end
