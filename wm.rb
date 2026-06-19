
require_relative 'floating'
require_relative 'monitor'

class WindowManager
  attr_reader :dpy, :desktops, :windows, :focus

  def inspect = "<WindowManager>"

  def initialize dpy, config
    @dpy = dpy
    @windows = {}
    @monitors = []

    @border_normal = 0x88666666
    @border_focus  = 0xffff66ff

    process_config(config)
    
    change_property(:_NET_NUMBER_OF_DESKTOPS, :cardinal, @desktops.count)

    mask = X11::Form::ButtonPressMask|X11::Form::ButtonReleaseMask|X11::Form::PointerMotionMask
    # Grab Super+button1/3 (move/resize), ignoring the lock modifiers
    # (NumLock=Mod2, CapsLock=Lock) by grabbing every combination of them.
    lock_combos = [0, X11::Form::Mod2, X11::Form::Lock, X11::Form::Mod2|X11::Form::Lock]
    [1, 3].each do |button|
      lock_combos.each do |lock|
        root.grab_button(true, mask, :async, :async, 0, 0, button, X11::Form::Mod4|lock)
      end
    end

    eventmask = (X11::Form::SubstructureNotifyMask |
       X11::Form::SubstructureRedirectMask |
       X11::Form::StructureNotifyMask      |
       X11::Form::EnterWindowMask          |
       X11::Form::LeaveWindowMask          |
       X11::Form::ButtonPressMask          |
       X11::Form::ExposureMask             |
       X11::Form::KeyPressMask             |
       X11::Form::FocusChangeMask
     )

     root.select_input(eventmask)
     at_exit { root.set_input_focus(:parent) }

     children = root.query_tree.children
     children.each { |wid| window(wid) }

     desktops.each(&:hide)
     
     # Then show only the active desktop for each monitor
     @monitors.each do |monitor|
       if desktop = monitor.active_desktop
         desktop.show
       end
     end
     
     # Set current desktop ID property based on active monitor
     if active_monitor&.active_desktop
       set_current_desktop(active_monitor.active_desktop.id)
     else
       # Fallback to desktop 0 if no active desktop
       change_desktop(0)
     end

     setup_ewmh
  end

  # EWMH hints we actually honour. Advertised via _NET_SUPPORTED so toolkits
  # (and pagers/wmctrl) know an EWMH-compliant WM is running.
  SUPPORTED_HINTS = %i[
    _NET_SUPPORTING_WM_CHECK _NET_SUPPORTED
    _NET_NUMBER_OF_DESKTOPS _NET_CURRENT_DESKTOP
    _NET_ACTIVE_WINDOW _NET_CLIENT_LIST _NET_CLOSE_WINDOW
    _NET_WM_DESKTOP _NET_WM_STATE _NET_WM_STATE_FULLSCREEN
    _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DESKTOP
    _NET_WM_WINDOW_TYPE_DOCK _NET_WM_WINDOW_TYPE_DIALOG
  ].freeze

  # Advertise EWMH compliance: a persistent child window referenced by
  # _NET_SUPPORTING_WM_CHECK on both the root and itself, named via
  # _NET_WM_NAME, plus the _NET_SUPPORTED hint list on the root.
  def setup_ewmh
    @check_window = @dpy.create_window(-1, -1, 1, 1,
      depth: rootgeom.depth,
      values: { X11::Form::CWOverrideRedirect => 1 })
    win_bytes = [@check_window].pack("V*").unpack("C*")
    @dpy.change_property(:replace, root.wid,      :_NET_SUPPORTING_WM_CHECK, :window, 32, win_bytes)
    @dpy.change_property(:replace, @check_window, :_NET_SUPPORTING_WM_CHECK, :window, 32, win_bytes)
    change_property(:_NET_SUPPORTED, :atom, SUPPORTED_HINTS.map { dpy.atom(_1) })
    # FIXME: Also set _NET_WM_NAME ("rubywm", UTF8_STRING) on the check window.
    # Blocked by a pure-x11 ChangeProperty bug: it sizes the request for 4-byte
    # padded data but emits the raw bytes, so any format-8 property whose length
    # isn't a multiple of 4 raises "BAD LENGTH". (Same bug Rebar pads around.)
  rescue => e
    $logger.error("setup_ewmh failed: #{e.class}: #{e.message}")
  end

  def set_current_desktop(desktop)
    @current_desktop_id = desktop
    change_property(:_NET_CURRENT_DESKTOP, :cardinal, desktop)
    change_property("_NET_CURRENT_DESKTOP_MONITOR_#{active_monitor.id}".to_sym, :cardinal, desktop)
  end
  
  def process_node_child(spec, n)
    if spec[:type] != :node && !spec[:nodes]
      return Leaf.new(iclass: spec[:iclass], parent: n)
    end
    cur = Node.new(parent: n)
    process_node_config(cur, spec, n)
    return cur
  end

  def process_node_config(n, spec, parent=nil)
    n.ratio = spec[:ratio] if spec&.dig(:ratio)
    n.dir = spec[:dir].to_sym if spec&.dig(:dir)
    Array(spec&.dig(:nodes)).each do |sub|
      n.nodes << process_node_child(sub, n)
    end
  end

  def process_monitors
    monitors = @dpy.xinerama_query_screens.screens

    if monitors.empty?
      # Create a default monitor using root geometry if none defined
      geom = rootgeom
      @primary_monitor = WM::Monitor.new(0, 
                                    width: geom.width, 
                                    height: geom.height, 
                                    xoffset: 0, 
                                    yoffset: 0)
      @monitors = [@primary_monitor]
    else
      monitors.each_with_index do |screen, id|
        monitor = WM::Monitor.new(id, 
                             width: screen.width,
                             height: screen.height,
                             xoffset: screen.x_org,
                             yoffset: screen.y_org)
        @monitors[id] = monitor
        
        # First monitor in config becomes primary by default
        @primary_monitor ||= monitor
      end
    end
    $logger.info("Monitors: #{@monitors.inspect}")
  end
  
  # Find the monitor that contains a given point
  def monitor_for_point(x, y)
    @monitors.find do |monitor|
      x >= monitor.xoffset && x < (monitor.xoffset + monitor.width) &&
      y >= monitor.yoffset && y < (monitor.yoffset + monitor.height)
    end
  end
  
  # Get the current pointer position
  def pointer_position
    query = @dpy.query_pointer(root.wid)
    return query.root_x, query.root_y
  rescue X11::Error => e
    $logger.debug { "error getting pointer position: #{e.message}" }
    return nil, nil
  end

  # Get the monitor containing the mouse pointer, falling back to the focused
  # window's monitor and then the primary monitor.
  def active_monitor
    x, y = pointer_position

    if x.nil? || y.nil?
      return @focus ? monitor_for_window(@focus) : @primary_monitor
    end

    monitor_for_point(x, y)
  end
  
  # Find the monitor that contains a window (using center point)
  def monitor_for_window(window)
    geom = window.get_geometry
      
    return @primary_monitor if !geom || geom.is_a?(X11::Form::Error)
      
    # Get center point of window
    center_x = geom.x + (geom.width / 2)
    center_y = geom.y + (geom.height / 2)
      
    # Find monitor containing this point
    monitor = monitor_for_point(center_x, center_y)
      
    # Always return a monitor - use primary if no matching monitor found
    monitor || @primary_monitor
  rescue X11::Error => e
    $logger.debug { "error finding monitor for window #{window.wid}: #{e.message}" }
    @primary_monitor
  end

  # FIXME: I'm not particlarly happy about building this in.
  # I prefer the bspwm approach of externalising it, because
  # I need/want an API to change it dynamically anyway, so
  # this is likely to change.
  def process_config(config)
    process_monitors

    # FIXME: Move to each monitor.
    @floating = FloatingLayout.new(self, rootgeom)

    num_desktops = config.dig(:desktops, :number) || 10
    @desktops ||= num_desktops.times.map do |num|
      c = config.dig(:desktops, num+1)
      name = c&.dig(:name) || (num+1).to_s
      Desktop.new(self, num, name).tap do |d|

        # FIXME: Check EWMH hints first.
        # Associate desktop with monitor for per-monitor desktop support
        # On startup, each monitor shows a different desktop in sequence
        # (monitor 1 shows desktop 1, monitor 2 shows desktop 2, etc.)
        if num < @monitors.size
          monitor = @monitors[num]
          monitor.active_desktop = d
        end
        
        if c&.dig(:layout) == "floating"
          # FIXME: Should be ok to set this to @floating
          # but some logic checks for a nil layout
          d.layout = nil
        else
          # Use monitor-specific geometry for the layout
          d.layout = TiledLayout.new(d, d.geometry)
          process_node_config(d.layout.root, c)
        end
      end
    end
  end
  

  def change_property(atom, type, data, mode: :replace, format: 32)
    root.change_property(mode, atom, type, format, Array(data).pack("V*").unpack("C*"))
  end

  def current_desktop_id = (@current_desktop_id ||= root.get_property(:_NET_CURRENT_DESKTOP, :cardinal)&.value.to_i)
  def current_desktop    = desktops[current_desktop_id] || desktops[0]
  def root_id            = (@root_id ||= @dpy.screens.first.root)
  def root               = (@root ||=Window.new(self, root_id))
  def layout
    $logger.warn("Calling wm.layout almost certainly means this code path is not multi-monitor safe. FIXME.")
    $logger.warn("Code that calls this should be converted to find the actual layout for the given window")
    $logger.warn(caller[0..9].inspect)
    current_desktop&.layout || @floating
  end
  
  def layout_for(w)
    if w.floating?
      # Ensure floating layout knows about the desktop
      @floating.set_desktop(w.desktop) if w.desktop
      return @floating
    else
      desktop = w.desktop
      current_layout = layout
      
      # For tiled layout, make sure it's using current desktop's geometry
      if current_layout.is_a?(TiledLayout) && desktop&.monitor
        current_layout.update_geometry(desktop.geometry)
      end
      
      return current_layout
    end
  end
  
  def update_layout
    @monitors.each {|m| m.active_desktop&.layout&.call(@focus) }
  end

  # FIXME: Does not take into account panels
  def rootgeom           = (@rootgeom ||= root.get_geometry)
  def window(wid)
    return root if (wid == root.wid)
    return @windows[wid] if @windows[wid]
    adopt(wid)
  end

  def with_window(wid)
    w = window(wid)
    yield(w) if w
  end
  
  def update_client_list = change_property(:_NET_CLIENT_LIST, :window, @windows.keys)

  # If we don't already know about this window, we "adopt" it.
  def adopt(wid, desktop=nil)
    return if wid.nil?
    w = @windows[wid] # To avoid infinite recursion, this *must not* use #window
    return w if w
    w = Window.new(self, wid)

    # FIXME: At least some of these ought to "adopted" but set as
    # floating/non-layout so they stay on a single desktop.
    #
    if w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_POPUP) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_NOTIFICATION) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_POPUP_MENU) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_MENU) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_DOCK) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_TOOLTIP) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_DIALOG) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_SPLASH) ||
      w.type == dpy.atom(:_NET_WM_WINDOW_TYPE_UTILITY)
      w.floating = true
      w.stack
      return w
    end
    if w.desktop?
      w.floating = true
    end
    attr = w.get_window_attributes rescue nil
    return w if !attr
    return w if attr.wclass == 2 # InputOnly
    return w if attr.override_redirect
    w.mapped = attr.map_state != 0
    geom = w.get_geometry
    return w if geom.width < 2 || geom.height < 2
    @windows[wid] = w

    wms = w.get_property(:_NET_WM_STATE, :atom)&.value
    if wms == dpy.atom(:_NET_WM_STATE_ABOVE)
      # This seems like it's probably not a good idea.
      return w
    end

    w.set_border(@border_normal)

    desktop = dpy.get_property(wid, :_NET_WM_DESKTOP, :cardinal)&.value
    if !desktop
      monitor = active_monitor
      desktop = monitor.active_desktop.id
    end
    move_to_desktop(wid, desktop)
    w.select_input(
      X11::Form::FocusChangeMask     |
      X11::Form::PropertyChangeMask  |
      X11::Form::EnterWindowMask     |
      X11::Form::LeaveWindowMask
    )
    update_client_list
    return w
  end

  def map_window(wid)
    with_window(wid) do |w|
      w.mapped = true
      
      # If the window is new, position it on appropriate monitor
      if !layout_for(w).find(w)
        monitor = active_monitor
        desktop = active_monitor.active_desktop
        
        # Get the layout that will be used
        win_layout = layout_for(w)
        
        # For tiled layout, force geometry update based on monitor
        if !w.floating? && win_layout.is_a?(TiledLayout)
          # Force the layout to use the current monitor's geometry
          win_layout.update_geometry(desktop.geometry)
        end
        
        # Associate floating layout with the desktop if needed
        if w.floating?
          @floating.set_desktop(nil) # Reset first
          @floating.set_desktop(desktop)
        end
        
        # Now place the window using the layout with updated monitor information
        win_layout.place(w, @focus)
      end
      
      w.map
      set_focus(wid) unless w.special?
    end
  end

  def move_to_desktop(wid,desktop)
    return if wid == root_id
    d = desktops[desktop] || desktops[0]
    w = window(wid)
    old = w.desktop

    return if old == d

    if !w.floating?
      old&.layout&.remove_window(w)
    end

    w.desktop = d
    
    if d.active?
      w.show
      
      # If moving to an active desktop, add to layout and update focus
      if !w.floating? && d.layout
        d.layout.place(w, @focus)
      end
    else
      w.hide
    end
    
    d.update_layout if d.active?
    old.update_layout if old&.active?
  end

  def change_desktop(d) = change_desktop_on_monitor(active_monitor, d)
    
  def change_desktop_on_monitor(curr_monitor, d)
    target_desktop = desktops[d] if !d.is_a?(Desktop)
    return if !target_desktop
    
    current_monitor_desktop = curr_monitor.active_desktop
    
    # If we're already showing this desktop on current monitor, just update layout
    if current_monitor_desktop&.id == d
      update_layout
      return current_monitor_desktop.show
    end
    
    # Try to find if any other monitor is showing the target desktop
    other_monitors_with_target = @monitors.select do |m| 
      m != curr_monitor && 
      m.active_desktop && 
      m.active_desktop.id == target_desktop.id
    end
    
    # Use the first one found if any
    other_monitor = other_monitors_with_target.first
    
    current_monitor_desktop&.hide

    # If the target monitor is shown on another monitor, swap that monitor to this
    # monitors desktop
    if other_monitor
      current_monitor_desktop.monitor = nil
      change_desktop_on_monitor(other_monitor, current_monitor_desktop.id)
    end
    
    # Update desktop-monitor association
    curr_monitor.active_desktop = target_desktop
      
    # Make sure layout geometry is updated 
    if target_desktop.layout
      target_desktop.layout.update_geometry(curr_monitor.geometry)
    else
      @floating.set_desktop(target_desktop)
      @floating.update_geometry(curr_monitor.geometry)
    end
      
    # Show the desktop
    target_desktop.show

    # FIXME: pass monitor id
    set_current_desktop(d)
    
    update_layout
    
    # Set focus to first window if available
    f = target_desktop&.mapped_regular_children&.first
    set_focus(f.wid) if f
  end


  def set_focus(wid)
    return if wid == root_id
    with_window(wid) do |w|
      w = window(wid)
    
      # FIXME: This may be a bit brutal, in that it prevents keyboard control of the desktop or dock.
      return if w.special?
    
      @focus&.set_border(@border_normal)
      @focus = w
      @focus.set_input_focus(:parent)
      @focus.set_border(@border_focus)
      change_property(:_NET_ACTIVE_WINDOW, :window, wid)
    end
  end

  def destroy_window(wid)
    if @windows[wid]
      @windows.delete(wid)
      update_layout
      update_client_list
    end
  end
  
  # # X Event-handlers

  def on_error(ev) = destroy_window(ev.bad_resource_id)

  def on_map_notify(ev)      = (window(ev.window)&.mapped = true)
  def on_unmap_notify(ev)    = (window(ev.window)&.mapped = false)
  def on_map_request(ev)     = map_window(ev.window)

  # ConfigureWindow value-mask bits and stack_mode values (X11 core protocol).
  CONFIGURE_FIELDS = { 0x01 => :x, 0x02 => :y, 0x04 => :width,
                       0x08 => :height, 0x10 => :border_width }.freeze
  STACK_MODES = { 0 => :above, 1 => :below, 2 => :top_if,
                  3 => :bottom_if, 4 => :opposite }.freeze

  # A client asked to reconfigure itself. Because we hold SubstructureRedirect
  # the server applied nothing and handed us the request. Honour it for
  # floating/unmanaged windows (dialogs, pickers sizing themselves); for tiled
  # windows the WM owns geometry, so re-assert the tile, which still sends the
  # client a ConfigureNotify telling it its real size.
  def on_configure_request(ev)
    w = @windows[ev.window]
    if w && !w.floating?
      w.resize_to_geom(w.realgeom) if w.realgeom
      return
    end

    args = CONFIGURE_FIELDS.each_with_object({}) do |(bit, field), h|
      h[field] = ev.send(field) if ev.value_mask & bit != 0
    end
    args[:stack_mode] = STACK_MODES[ev.stack_mode] if ev.value_mask & 0x40 != 0
    return if args.empty?

    w ? w.configure(**args) : @dpy.configure_window(ev.window, **args)
  rescue X11::Error => e
    $logger.debug { "error configuring #{ev.window}: #{e.message}" }
  end
  def on_property_notify(ev)
    name = dpy.get_atom_name(ev.atom) rescue nil
    $logger.info("Property Notify: #{name}")
  end

  def on_button_press(ev)
    return if !ev.child
    w = window(ev.child)
    @attr = w.get_geometry
    set_focus(w.wid)
    @start = ev
  end

  def on_motion_notify(ev)
    # @start.button == 1 -> move
    # @start.button == 3 -> resize
    set_focus(ev.child) if ev.child != @start.child
    return if !@start&.child || !@attr

    xdiff = ev.root_x - @start.root_x;
    ydiff = ev.root_y - @start.root_y;

    w = window(@start.child)

    # FIXME: Any other types we don't want to allow moving or resizing
    return if w.special?

    if @start.detail == 1 # Move
      if w.floating?
        w.configure(x: @attr.x + xdiff, y: @attr.y + ydiff)
      end
    elsif @start.detail == 3 # Resize
      lr = (ev.event_x-@attr.x < @attr.width / 2)
      tb = (ev.event_y-@attr.y < @attr.height/ 2)
      if w.floating?
        # If left/above the centre point, we grow/shrink the window to the left/top
        # otherwise to the right/bottom. Doing it to the left/top requires
        # moving it at the same time.
        @attr.x = @attr.x + (lr ? xdiff : 0)
        @attr.y = @attr.y + (tb ? ydiff : 0)
        @attr.width  = @attr.width + (lr ? -xdiff : xdiff)
        @attr.height = @attr.height+ (tb ? -ydiff : ydiff)
        w.configure(x: @attr.x, y: @attr.y, width: @attr.width, height: @attr.height)
      else
        ancestors = ->(first,dir,flag, &block) do
          first&.ancestors&.each_cons(2) do |prev, node|
            if node.dir == dir &&
              ((node.nodes[0] == prev && !flag) ||
              (node.nodes[1] == prev))
              node.ratio += node.geom ? block.call(prev,node,flag) : 0.0
              node.ratio = node.ratio.clamp(0.1,0.9)
              return
            end
          end
        end

        ancestors.call(w.layout_leaf,:lr,lr) do |prev, node, flag|
          (((node.geom.width * node.ratio) + xdiff)/node.geom.width) - node.ratio
        end
          
        ancestors.call(w.layout_leaf, :tb, tb) do |prev,node, flag|
          (((node.geom.height * node.ratio) + ydiff)/node.geom.height) - node.ratio
        end
        update_layout
      end
      @start.root_x = ev.root_x
      @start.root_y = ev.root_y
    end
  end

  def on_button_release(ev) = (@start.child = nil if @start)
  def on_focus_in(ev)       = focus || set_focus(ev.event)
  def on_enter_notify(ev)   = set_focus(ev.event)
  def on_destroy_notify(ev) = destroy_window(ev.window)

  # # Client Messages

  def on_net_active_window(wid, ...) = map_window(wid)

  def on_net_restack_window(wid,source, sibling_wid, detail)
    w = window(wid)

    # FIXME: Handle sibling.
    detail = case detail
      when 0 then :above
      when 1 then :below
      else detail
      end
    w.configure(stack_mode: detail)
  end

  def on_net_current_desktop(_, d) = change_desktop(d)

  def on_net_wm_state(wid, action, prop1, prop2, source)
    with_window(wid) do |w|
      # FIXME: Need to check if "action" for toggle vs set/clear
      [prop1, prop2].each do |prop|
        case prop
        when dpy.atom(:_NET_WM_STATE_FULLSCREEN)
          w&.toggle_maximize
        end
      end
      # For the time being, we recognize two things only:
      # NET_WM_STATE_FULLSCREEN and NET_WM_STATE_MAXIMIZED_{VERT,HORZ}
    end
  end

  def on_net_wm_desktop(wid, d) = move_to_desktop(wid, d)

  # EWMH: ask the WM to close a specific window gracefully.
  def on_net_close_window(wid, *) = window(wid)&.request_close

  # Close the focused window (kept for the keybinding that sends this to root).
  def on_wm_delete_window(*) = @focus&.request_close

  # # RWM specific ClientMessages
  

  # Move window to the desktop shown on adjacent monitor
  # Usage: xclimsg -mp _RWM_MOVE_TO_MONITOR <direction>
  # Direction: "next" or "previous"
  def on_rwm_move_to_monitor(_, direction_atom)
    return unless @focus
    
    direction = dpy.get_atom_name(direction_atom).downcase.to_sym
    return unless [:next, :previous].include?(direction)
    
    curr_index = @monitors.index(active_monitor)
    return if curr_index.nil?

    offset = direction == :next ? 1 : -1
    target_monitor = @monitors[(curr_index + offset) % @monitors.size]
    target_desktop = target_monitor.active_desktop
    return unless target_desktop
    
    move_to_desktop(@focus.wid, target_desktop.id)
    set_focus(@focus.wid)
  end
  

  # Move focus to the "nearest" window in `dir` direction
  def on_rwm_focus(_, dir)
    dir = dpy.get_atom_name(dir).downcase.to_sym
    return if !@focus || @focus.special?
    w = find_closest(@focus, dir, @focus.desktop.mapped_regular_children)
    set_focus(w.wid) if w
  end

  # Toggle the direction of the node split.
  def on_rwm_shift_direction(_,dir)
    # FIXME: Respect the window passed instead of doing it to @focus
    return if !@focus || @focus.special?
    if node = layout.find(@focus)
      node = node.parent if node.is_a?(Leaf)
      node.dir = node.dir == :lr ? :tb : :lr
      current_desktop&.update_layout
    end
  end

  # Swap nodes in the nearest parent node of the focused window
  def on_rwm_swap_nodes(_)
    # FIXME: Respect the window passed instead of doing it to @focus
    # no matter what
    return if !@focus || @focus.special?
    # FIXME: Move to layout?
    if node = layout.find(@focus)
      node = node.parent if node.is_a?(Leaf)
      tmp = node.nodes[0]
      node.nodes[0] = node.nodes[1]
      node.nodes[1] = tmp
      update_layout
    end
  end

  # Move the focused window, either swapping it into the container
  # of the nearest leaf (if tiled), or moving it stepwise if floating
  # FIXME: Just have rwm move specify x/y *offsets* instead? Would
  # save an (admittedly cached) get_atom_name
  def on_rwm_move(_,dir)
    return if !@focus || @focus.special?
    dir = dpy.get_atom_name(dir).downcase.to_sym

    if @focus.floating?
      g = @focus.get_geometry

      case dir
      when :left  then @focus.configure(x: g.x - 20)
      when :right then @focus.configure(x: g.x + 20)
      when :down  then @focus.configure(y: g.y + 20)
      when :up    then @focus.configure(y: g.y - 20)
      end
      return
    end

    w = find_closest(@focus, dir, @focus.desktop.mapped_regular_children)

    l1 = @focus.desktop&.layout&.find(@focus)
    l2 = w&.desktop&.layout&.find(w)
    if l1 && l2
      l2.window = @focus
      l1.window = w
      @focus.desktop.update_layout

      # FIXME: We want to ensure focus stays in @focus
      # here. Not sure how. We get enter/leave/focus in/out
      # events. How can we get button/motion events for individual windows
      # Maybe I have to do
      # https://stackoverflow.com/questions/62448181/how-do-i-monitor-mouse-movement-events-in-all-windows-not-just-one-on-x11
      # XInput v2.0
      # And then ignore enter/leave events. Seems stupid
      # Investigate what Katriawm does?
      set_focus(@focus.wid)
    end
  end
end
