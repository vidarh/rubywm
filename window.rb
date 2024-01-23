
# FIXME: 10000 pixels should be enough for anyone ...
# Until it isn't.
HIDDEN_OFFSET=10000
# FIXME: Extract this from the real root width
MAX_WIDTH=1920

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
    @realgeom = get_geometry rescue nil
    @floating = floating

    # This is a "safety" workaround
    # during development to avoid "losing" windows

    if @realgeom && (@realgeom.x < 0 || @realgeom.x > MAX_WIDTH)
      # First try to strip the offset.
      if @realgeom.x >= HIDDEN_OFFSET
        @realgeom.x -= HIDDEN_OFFSET
      end

      # OK, if still out of bounds, let's just give up finding
      # the correct position.
      if @realgeom.x > MAX_WIDTH || @realgeom.x < 0
        @realgeom.x = 0
      end
      resize_to_geom(@realgeom)
    end

    (lower if desktop?) rescue nil
  end

  def mapped=(state)
    @mapped = state
    desktop&.update_layout
  end
  
  def hidden_offset = @hidden && @desktop ? HIDDEN_OFFSET : 0

  def layout_leaf = @desktop&.layout.find(self)
    
  # FIXME: This should be an explicit flag, because as it is
  # here we can't make a floating window on a tiling desktop.
  def floating? = @desktop&.layout.nil? || @floating

  def hide
    return if @hidden
    @hidden=true
    @realgeom = get_geometry rescue nil
    resize_to_geom(@realgeom) if @realgeom
  end

  def show
    return if !@hidden
    @hidden = false
    resize_to_geom(@realgeom) if @realgeom
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
      net_wm_desktop=d.id
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

  def wm_class = (@wm_class ||= get_property(:WM_CLASS, :STRING)&.value.to_s.split("\0"))
  def type = (@type ||= get_property(:_NET_WM_WINDOW_TYPE, :atom)&.value.to_i)

  def desktop? = (type == dpy.atom(:_NET_WM_WINDOW_TYPE_DESKTOP))
  def dock?    = (type == dpy.atom(:_NET_WM_WINDOW_TYPE_DOCK))
  def special? = (desktop? | dock?)

  # FIXME: Ensure any "desktop" windows on this desktop are moved *below*
  def lower =  configure(stack_mode: :below)
  def raise = (configure(stack_mode: :above) unless desktop?)

  # Adjust stacking based on type. This in incomplete
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
    
  # FIXME: Account for border.
  def maximize = resize_to_geom(@wm.rootgeom, stack_mode: :above)

  def resize_to_geom(geom, **args)
    # FIXME: Need to figure out what to do about these
    return if geom == X11::Form::Error
    configure(x: geom.x + hidden_offset, y: geom.y, width: geom.width, height: geom.height, **args)
  end

  def set_border(col, w=1)
    return configure(border_width: 0) if special?
    configure(border_width: w)
    change_attributes(values: {X11::Form::CWBorderPixel => col})
  end

  def toggle_maximize
    return if special?
    rootgeom = @wm.rootgeom

    geom = get_geometry rescue nil
    return if geom.nil?

    if (og = @old_geom) &&
      geom.x == 0 && geom.y == 0 &&
      geom.width  == rootgeom.width &&
      geom.height == rootgeom.height
      resize_to_geom(og)
    else
      # If maximized, and we know the old size, we revert the size.
      @old_geom = get_geometry # This is wasteful
      maximize
    end
  end
end
