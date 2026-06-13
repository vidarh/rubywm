

require_relative 'monitor'

class Desktop
  attr_accessor :name, :id, :wm, :layout, :window
  attr_reader :monitor
  
  def monitor=(monitor)
    return if @monitor == monitor
    old_monitor = @monitor
    @monitor = monitor
    if old_monitor&.active_desktop == self
      old_monitor.active_desktop = nil
    end
    @monitor&.active_desktop = self
  end

  def initialize(wm, id, name) = (@wm, @id, @name, @monitor = wm, id, name, nil)
  def active? = (@monitor&.active_desktop == self)

  def children = @wm.windows.values.find_all{_1.desktop==self}
  def mapped_regular_children = children.find_all{_1.mapped && !_1.special?}
  def show
    layout&.update_geometry(geometry)
    children.each(&:show)
  end
  
  def hide     = children.each(&:hide)
  
  def inspect
    "<Desktop id=#{id} monitor=#{@monitor&.name} window=#{@window}>"
  end
  
  def geometry = (@monitor&.geometry || @wm.rootgeom)
  def update_layout = (active? && layout&.call(@wm.focus))
end
