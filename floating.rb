#
# Apart from the very limited "place" the main purpose of this
# class is to ensure there *always* is a layout

require_relative 'layout'

class FloatingLayout < Layout
  def initialize(wm, rootgeom)
    @wm = wm
    @rootgeom = rootgeom
    @desktop = nil
  end

  # Update geometry when desktop monitor changes
  def update_geometry(geom)
    @rootgeom = geom
  end
  
  # Associate with a desktop
  def set_desktop(desktop)
    @desktop = desktop
  end
  
  def find(w) = nil
  
  def current_geometry = @wm.active_monitor.geometry #(@desktop&.geometry || @rootgeom)
    
  def place(w, focus)
    # Desktop windows are pinned to their own desktop (handled in map_window);
    # never re-place or reassign them here.
    return if w.desktop?

    attr = w.get_geometry
    return if attr.is_a?(X11::Form::Error)

    mon  = @wm.active_monitor
    geom = mon.geometry.dup

    # Default to 70% of the monitor only for windows that map at a degenerate
    # size; otherwise respect the size the client asked for.
    if attr.width < 10 || attr.height < 10
      width  = (geom.width  * 0.7).to_i
      height = (geom.height * 0.7).to_i
    else
      width  = attr.width
      height = attr.height
    end

    if attr.x == 0 && attr.y == 0
      # No requested position: centre on the active monitor.
      x = mon.xoffset + (geom.width  - width)  / 2
      y = mon.yoffset + (geom.height - height) / 2
    else
      # The client requested an absolute position (e.g. a saved location). Such
      # positions are screen-absolute, so honouring them verbatim opens the
      # window on whatever monitor those coordinates fall on rather than the one
      # you're working on. Re-anchor it to the *same position relative to its
      # monitor* on the active monitor, then clamp it on-screen.
      src = @wm.monitor_for_point(attr.x, attr.y) || mon
      x = mon.xoffset + (attr.x - src.xoffset)
      y = mon.yoffset + (attr.y - src.yoffset)
      x = x.clamp(mon.xoffset, [mon.xoffset, mon.xoffset + geom.width  - width].max)
      y = y.clamp(mon.yoffset, [mon.yoffset, mon.yoffset + geom.height - height].max)
    end

    geom.x = x
    geom.y = y
    geom.width = width
    geom.height = height

    w.desktop = mon.active_desktop
    w.resize_to_geom(geom)
  rescue X11::Error => e
    $logger.debug { "error placing window #{w.wid}: #{e.message}" }
  end
end
