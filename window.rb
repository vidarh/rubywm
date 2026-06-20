
# FIXME: 10000 pixels should be enough for anyone ...
# Until it isn't.
HIDDEN_OFFSET=10000

# ICCCM WM_STATE values
WITHDRAWN_STATE = 0
NORMAL_STATE    = 1
ICONIC_STATE    = 3

class Window < X11::Window
  attr_reader :desktop, :hidden, :mapped, :realgeom
  attr_writer :floating

  def eql?(other) = (wid == other&.wid)
  def ==(other) = eql?(other)
  # eql? is overridden by wid, so hash must match it for Set/Array membership
  # (e.g. `windows - @root.children` in the tiled layout) to work.
  def hash = wid.hash

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

  # ICCCM WM_STATE so pagers/clients know whether we consider a window
  # mapped (Normal) or hidden (Iconic).
  def set_wm_state(state)
    change_property(:replace, :WM_STATE, dpy.atom(:WM_STATE), 32,
                    [state, 0].pack("V*").unpack("C*"))
  rescue X11::Error => e
    $logger.debug { "error setting WM_STATE on #{wid}: #{e.message}" }
  end

  def hide
    return if @hidden
    @hidden=true
    @realgeom = get_geometry
    resize_to_geom(@realgeom)
    set_wm_state(ICONIC_STATE)
  end

  def show
    return if !@hidden
    @hidden = false
    set_wm_state(NORMAL_STATE)

    # A desktop window follows its desktop to whatever monitor shows it and
    # fills that monitor; it is not relocated like an ordinary floating window.
    if desktop?
      resize_to_geom(@desktop&.geometry || @wm.rootgeom)
      lower
      return
    end

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
    set_wm_state(NORMAL_STATE)
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

  # Window types we never tile: floated, stacked above, kept on a single
  # desktop. The corresponding atom ids are interned once on the WM (see
  # WindowManager#float_type_atoms) so this stays cheap on hot paths.
  FLOAT_TYPES = %i[
    _NET_WM_WINDOW_TYPE_DIALOG _NET_WM_WINDOW_TYPE_UTILITY
    _NET_WM_WINDOW_TYPE_SPLASH _NET_WM_WINDOW_TYPE_TOOLTIP
    _NET_WM_WINDOW_TYPE_MENU   _NET_WM_WINDOW_TYPE_POPUP_MENU
    _NET_WM_WINDOW_TYPE_POPUP  _NET_WM_WINDOW_TYPE_NOTIFICATION
  ].freeze

  def floaty_type? = @wm.float_type_atoms.include?(type)

  # FIXME: Ensure any "desktop" windows on this desktop are moved *below*
  def lower =  configure(stack_mode: :below)
  def raise = (configure(stack_mode: :above) unless desktop?)

  # Adjust stacking based on type. This is incomplete
  def stack
    return lower if desktop?
    return self.raise if dock? || floaty_type?
  end
    
  def maximize = (set_border_width(0) and resize_to_geom(desktop&.geometry || @wm.rootgeom, stack_mode: :above))

  # Ask the client to close itself via WM_DELETE_WINDOW if it advertises the
  # protocol (so it can prompt to save etc.); otherwise destroy it outright.
  def request_close
    protocols = Array(get_property(:WM_PROTOCOLS, :atom)&.value)
    if protocols.include?(dpy.atom(:WM_DELETE_WINDOW))
      dpy.client_message(window: wid, destination: wid, type: :WM_PROTOCOLS,
                         format: 32, mask: 0, propagate: false,
                         data: [dpy.atom(:WM_DELETE_WINDOW), 0])
    else
      destroy
    end
  rescue X11::Error => e
    $logger.debug { "error closing #{wid}: #{e.message}" }
  end

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
      @realgeom = @old_geom if @old_geom
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
