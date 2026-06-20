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

    geom = current_geometry.dup

    # Default to 70% of the monitor only for windows that map at a degenerate
    # size; otherwise respect the size the client asked for.
    if attr.width < 10 || attr.height < 10
      width  = (geom.width  * 0.7).to_i
      height = (geom.height * 0.7).to_i
    else
      width  = attr.width
      height = attr.height
    end

    # Centre on the current monitor unless the client gave an explicit position.
    x = attr.x == 0 ? (geom.width  - width)  / 2 : attr.x
    y = attr.y == 0 ? (geom.height - height) / 2 : attr.y

    geom.x += x
    geom.y += y
    geom.width = width
    geom.height = height

    w.desktop = @wm.active_monitor.active_desktop
    w.resize_to_geom(geom)
  rescue X11::Error => e
    $logger.debug { "error placing window #{w.wid}: #{e.message}" }
  end
end
