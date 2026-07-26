

require_relative 'monitor'

class Desktop
  FLAG_STATIC         = 1 << 0
  FLAG_PINNED         = 1 << 1
  FLAG_DESKTOP_WINDOW = 1 << 2
  FLAG_GROUP_ROOT     = 1 << 3
  FLAG_SLOT_BACKED    = 1 << 4
  FLAG_AVAILABLE      = 1 << 5

  MODE_CODES = { tiled: 0, floating: 1 }.freeze

  attr_accessor :name, :id, :wm, :layout, :window, :key, :project, :group,
                :mode, :flags

  def initialize(wm, id, name, key: nil, project: nil, group: nil,
                 mode: :tiled, flags: 0)
    @wm, @id, @name = wm, id, name
    @key = (key || "desktop-#{id + 1}").to_s
    @project = project&.to_s
    @group = group&.to_s
    @mode = mode.to_sym
    @flags = flags.to_i
  end

  def mode_code = MODE_CODES.fetch(mode, MODE_CODES[:tiled])
  def static? = (flags & FLAG_STATIC != 0)
  def pinned? = (flags & FLAG_PINNED != 0)
  def desktop_window? = (flags & FLAG_DESKTOP_WINDOW != 0)
  def group_root? = (flags & FLAG_GROUP_ROOT != 0)
  def slot_backed? = (flags & FLAG_SLOT_BACKED != 0)
  def available_placeholder? = (flags & FLAG_AVAILABLE != 0)

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
