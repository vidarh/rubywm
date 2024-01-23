
class Leaf
  attr_accessor :window, :parent
  attr_accessor :iclass

  def inspect = "<Leaf @window=#{@window.inspect}, @iclass=#{@iclass} @parent=#{@parent.object_id}>"
  
  def initialize(window=nil, parent: nil, iclass: nil)
    @window, @parent, @iclass = window, parent, iclass
  end

  def children = @window
  def placements = @iclass ? self : nil

  def ancestors # FIXME this is misleading since it includes self.
    acc = [self]
    node = self
    while node = node.parent
      acc << node
    end
    acc
  end
  
  def keep(k)
    if !k.member?(window)
      return nil if !@iclass
      @window = nil
    else
      k.delete(window)
    end
    self
  end

  def accept(w)
    return false if @window
    return false if @iclass &&
      @iclass != w.wm_class.last &&
      @iclass != w.wm_class.first
    @window = w
    return true
  end
  
  def layout(geom, ...) = window&.resize_to_geom(geom)
  def find(w) = (@window == w ? self : nil)
end
