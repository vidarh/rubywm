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
    begin
      attr = w.get_geometry
      return if attr.is_a?(X11::Form::Error)
      
      geom = current_geometry.dup
      
      pp [:placing_window, w.wid, @desktop&.id, geom.inspect, attr.inspect]
      
      # Get the original window's dimensions
      orig_width = attr.width
      orig_height = attr.height
      
      # Only apply default sizes for windows that explicitly request it with small dimensions
      # Do not use position (x,y) for determining if sizing is needed
      needs_sizing = orig_width < 10 || orig_height < 10
      
      if needs_sizing
        # For windows that need sizing, use 70% of monitor dimensions consistently
        # FIXME: FOr some weird reason "geom" is the window dimensions, not
        # monitor dimensions. This is a bug somewhere.
        width  = (geom.width  * 0.7).to_i
        height = (geom.height * 0.7).to_i
        
        pp [:applying_default_size, monitor: geom.width, size: width, monitorx: geom.x]
      else
        # For windows with proper dimensions, always respect the requested size
        width = orig_width
        height = orig_height
        
        pp [:respecting_requested_size, width, height]
      end

      pp [:attr, attr]
      # Always place in center of current monitor
      x = attr.x == 0 ? (geom.width - width) / 2 : attr.x
      y = attr.y == 0 ? (geom.height - height) / 2 : attr.y

      pp [geom, x,y]
      geom.x += x #x += geom.x
      geom.y += y #y += geom.y
      geom.width = width
      geom.height = height
      
      pp [:positioning_at, geom, needs_sizing: needs_sizing]

      #w.floating = true
      w.desktop = @wm.active_monitor.active_desktop
      w.resize_to_geom(geom) #
      #w.configure(x:, y:, width:, height:)
    rescue X11::Error => e
      # Window might be gone or invalid
      pp [:error_placing_window, w.wid, e.message]
    end
  end
end
