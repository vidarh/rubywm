

require_relative 'monitor'

class Desktop
  attr_accessor :name, :id, :wm, :layout, :window

  def initialize(wm, id, name) = (@wm, @id, @name = wm, id, name)

  # Derived from the monitors: the monitor (if any) currently showing this
  # desktop. Monitor#active_desktop is the single source of truth.
  def monitor = @wm.monitors.find { _1.active_desktop == self }
  def active? = !monitor.nil?

  def children = @wm.windows.values.find_all{_1.desktop==self}
  def mapped_regular_children = children.find_all{_1.mapped && !_1.special?}
  def show
    layout&.update_geometry(geometry)
    children.each(&:show)
  end
  
  def hide     = children.each(&:hide)
  
  def inspect
    "<Desktop id=#{id} monitor=#{monitor&.id} window=#{@window}>"
  end

  def geometry = (monitor&.geometry || @wm.rootgeom)
  # Usable area for tiling: the monitor minus any dock struts.
  def work_area = @wm.work_area(monitor)
  def update_layout = (active? && layout&.call(@wm.focus))
end
