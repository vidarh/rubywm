
# FIXME: 10000 pixels should be enough for anyone ...
# Until it isn't.
HIDDEN_OFFSET=10000

class Window < X11::Window
  attr_reader :desktop, :hidden, :mapped
  attr_writer :floating

  def eql?(other) = (wid == other&.wid)
  def ==(other) = eql?(other)

  def initialize(wm, wid, desktop=nil, floating: false)
    super(wm.dpy, wid)
    @wm = wm
    self.desktop = desktop
    @hidden = false
    @realgeom = get_geometry
    @floating = floating

    # This is a "safety" workaround
    # during development to avoid "losing" windows

    if @realgeom
      # Try to strip hidden offset if set
      if @realgeom.x >= HIDDEN_OFFSET
        @realgeom.x -= HIDDEN_OFFSET
      end

      # Check if window is outside any visible monitor
      if !wm.monitor_for_point(@realgeom.x, @realgeom.y)
        # If outside all monitors, place on primary monitor
        @realgeom.x = 0
        @realgeom.y = 0
        resize_to_geom(@realgeom)
      end
    end

    lower if desktop?
  end

  def mapped=(state)
    @mapped = state
    desktop&.update_layout
  end
  
  def hidden_offset = @hidden && @desktop ? HIDDEN_OFFSET : 0
  def layout_leaf = @desktop&.layout.find(self)
  def floating? = @desktop&.layout.nil? || @floating

  def hide
    return if @hidden
    @hidden=true
    @realgeom = get_geometry
    resize_to_geom(@realgeom)
  end

  def show
    return if !@hidden
    @hidden = false
    begin
      # If this is a floating window on a desktop with a monitor
      if floating? && @desktop && (monitor = @desktop.monitor)
        # Get the current geometry or use what we have saved
        current_geom = get_geometry rescue nil
        geom_to_use = current_geom || @realgeom

        # FIXME: This moves the window more than necessary.
        # Should only force the window into the monitors viewport.
        if geom_to_use
          while geom_to_use.x >= HIDDEN_OFFSET
            geom_to_use.x -= HIDDEN_OFFSET
          end

          win_monitor = @wm.monitor_for_point(geom_to_use.x, geom_to_use.y)

          if !win_monitor
            while geom_to_use.x >= monitor.xoffset + monitor.width
              geom_to_use.x -= monitor.width
            end

            if geom_to_use.x < 0
              geom_to_use.x = 0
            end
            win_monitor = @wm.monitor_for_point(geom_to_use.x, geom_to_use.y)
          end

          if win_monitor && monitor != win_monitor
            xoff = monitor.xoffset - win_monitor.xoffset
            yoff = monitor.yoffset - win_monitor.yoffset

            # Create a new geometry with adjusted position
            resized_geom = geom_to_use.dup
            resized_geom.x += xoff
            resized_geom.y += yoff

            @realgeom = resized_geom
          end
        end
      end
      # Actually show the window with its geometry
      resize_to_geom(@realgeom) if @realgeom
    rescue X11::Error => e
      $logger.debug { "error showing window #{wid}: #{e.message}" }
    end
  end

  # We should rarely map a window ourselves, but if we do,
  # we should enforce the stacking.
  def map
    super
    stack
  end
  
  def desktop= d
    hide if @desktop&.active?
    @desktop = d
    d&.active? ? show : hide
    
    if d && !d.is_a?(Symbol)
      change_property(:replace, :_NET_WM_DESKTOP, :cardinal, 32, [d.id,0,0,0])
    end
  end

  def inspect
    d = (desktop||:unmanaged)
    d = d.is_a?(Symbol) ? d.inspect : d.id
    # This can fail if the window has been destroy or the connection severed, hence the rescue
    t = type == 0 ? 'None' : dpy.get_atom_name(type) rescue 'Unknown'
    "<Window wid=#{@wid.to_s(16)} desktop=#{d} type=#{t} mapped=#{@mapped}>"
  end

  def wm_class = get_property(:WM_CLASS, :STRING)&.value.to_s.split("\0")

  # FIXME: This can be an Array, and we should handle that properly, but for now let's just be defensive.
  def type     = (@type ||= Array(get_property(:_NET_WM_WINDOW_TYPE, :atom)&.value).first.to_i)

  def desktop? = (type == dpy.atom(:_NET_WM_WINDOW_TYPE_DESKTOP))
  def dock?    = (type == dpy.atom(:_NET_WM_WINDOW_TYPE_DOCK))
  def special? = (desktop? | dock?)

  # FIXME: Ensure any "desktop" windows on this desktop are moved *below*
  def lower =  configure(stack_mode: :below)
  def raise = (configure(stack_mode: :above) unless desktop?)

  # Adjust stacking based on type. This is incomplete
  def stack
    return lower if desktop?
    # FIXME: This is incomplete. Also may want to add a separate
    # classification method and cache result.
    return self.raise if dock? ||
         type == dpy.atom(:_NET_WM_WINDOW_TYPE_TOOLTIP) ||
         type == dpy.atom(:_NET_WM_WINDOW_TYPE_DIALOG) ||
         type == dpy.atom(:_NET_WM_WINDOW_TYPE_SPLASH) ||
         type == dpy.atom(:_NET_WM_WINDOW_TYPE_UTILITY)
  end
    
  def maximize = (set_border_width(0) and resize_to_geom(desktop&.geometry || @wm.rootgeom, stack_mode: :above))

  def resize_to_geom(geom, **args)
    # Skip if no geometry or invalid
    return if geom.nil? || geom == X11::Form::Error

    @realgeom = geom
    
    begin
      configure(x: geom.x + hidden_offset, y: geom.y, width: geom.width, height: geom.height, **args)
    rescue X11::Error => e
      $logger.debug { "error resizing window #{wid}: #{e.message}" }
    end
  end

  def set_border_width(w=1) = configure(border_width: special? ? 0 : w)
    
  def set_border(col, w=1)
    set_border_width(w)
    change_attributes(values: {X11::Form::CWBorderPixel => col}) unless special?
  end

  def toggle_maximize
    return if special?

    if @maximized == true
      @maximized = false
      @real_geom = @old_geom if @old_geom
      resize_to_geom(@realgeom)
      set_border_width
      desktop.update_layout
    else
      # If maximized, and we know the old size, we revert the size.
      @old_geom = get_geometry # This is wasteful
      maximize
      @maximized = true
    end
  end
end
