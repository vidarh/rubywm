#
# Apart from the very limited "place" the main purpose of this
# class is to ensure there *always* is a layout
#
class FloatingLayout

  def initialize(rootgeom)
    @rootgeom = rootgeom
  end

  def find(w) = nil
    
  def place(w, focus)
    attr = w.get_geometry
    return if attr.is_a?(X11::Form::Error)
    x = attr.x
    y = attr.y
    width  = attr.width
    height = attr.height
    width  = @rootgeom.width / 2 if width < 10
    height = @rootgeom.height - 100 if height < 10
    x = (@rootgeom.width  - width) /2 if x == 0
    y = (@rootgeom.height - height)/2 if y == 0
    w.configure(x:, y:, width:, height:)
  end

  def call = nil
end
