
class Leaf
  attr_accessor :window, :parent
  attr_accessor :iclass

  def inspect = "<Leaf @window=#{@window.inspect}, @iclass=#{@iclass} @parent=#{@parent.object_id}>"
  
  def initialize(window=nil, parent: nil, iclass: nil)
    @window, @parent, @iclass = window, parent, iclass
  end

  def children = @window
  def placements = @iclass ? self : nil

  def keep(k)
    return nil if !k.member?(window) && !@iclass
    p [:keep, self]
    self #return visible(window) ? self : nil
  end

  def layout(geom, gap=nil, dir = nil, level = nil)
    window.resize_to_geom(geom) if window
  end

  def find(w) = (@window == w ? self : nil)
end

