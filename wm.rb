
class WindowManager
  attr_reader :dpy, :desktops, :windows, :focus

  def inspect = "<WindowManager>"

  def initialize dpy, num_desktops: 10
    @dpy = dpy
    @windows = {}

    @border_normal = 0x88666666
    @border_focus  = 0xffff66ff

    @desktops ||= num_desktops.times.map do |num|
      Desktop.new(self, num, name: (num+1).to_s[-1])
    end
    
    # FIXME: Config
    (0..8).each do |i|
      desktops[i].layout = TiledLayout.new(desktops[i], rootgeom)
    end

    # FIXME: Config
    # FIXME: Improved way of specifying pre-designed layouts.
    r = desktops[1].layout.root
    r.nodes[0] = Leaf.new(iclass: "todo-todo")
    r.nodes[1] = Node.new([
      Leaf.new(iclass: "todo-done"),
      Leaf.new(iclass: "todo-note")],
      dir: :tb
    )

    change_property(:_NET_NUMBER_OF_DESKTOPS, :cardinal, num_desktops)

    mask = X11::Form::ButtonPressMask|X11::Form::ButtonReleaseMask|X11::Form::PointerMotionMask
    root.grab_button(true, mask, :async, :async, 0, 0, 1, X11::Form::Mod3)
    root.grab_button(true, mask, :async, :async, 0, 0, 3, X11::Form::Mod3)
    root.grab_button(true, mask, :async, :async, 0, 0, 1, X11::Form::Mod4)
    root.grab_button(true, mask, :async, :async, 0, 0, 3, X11::Form::Mod4)

    eventmask = (X11::Form::SubstructureNotifyMask |
       X11::Form::SubstructureRedirectMask |
       X11::Form::StructureNotifyMask      |
       X11::Form::EnterWindowMask          |
       X11::Form::LeaveWindowMask          |
       X11::Form::ButtonPressMask          |
#       X11::Form::ExposureMask             |
       X11::Form::KeyPressMask             |
       X11::Form::FocusChangeMask
     )

     root.select_input(eventmask)
     at_exit { root.set_input_focus(:parent) }

     children = root.query_tree.children
     children.each { |wid| window(wid) }

     desktops.each(&:hide)
     change_desktop(current_desktop_id)

  end

  def change_property(atom, type, data, mode: :replace, format: 32)
    root.change_property(mode, atom, type, format, Array(data).pack("V*").unpack("C*"))
  end

  def current_desktop_id = (@current_desktop_id ||= root.get_property(:_NET_CURRENT_DESKTOP, :cardinal)&.value.to_i)
  def current_desktop    = desktops[current_desktop_id] || desktops[0]
  def root_id            = (@root_id ||= @dpy.screens.first.root)
  def root               = (@root ||= X11::Window.new(@dpy, root_id))
  # FIXME: Does not take into account panels
  def rootgeom           = (@rootgeom ||= root.get_geometry)
  def window(wid)
    return root if (wid == root.wid)
    return @windows[wid] if @windows[wid]
    adopt(wid)
  end
  
  def update_client_list = change_property(:_NET_CLIENT_LIST, :window, @windows.keys)

  # If we don't already know about this window, we "adopt" it.
  def adopt(wid, desktop=nil)
    return if wid.nil?
    STDERR.puts "adopt: #{wid.to_s(16)}"
    w = @windows[wid] # To avoid infinite recursion, this *must not* use #window
    return w if w
    STDERR.puts "adopt: #{wid.to_s(16)} 2"
    w = Window.new(self, wid)
    begin
      STDERR.puts "\e[35madopt6\e[0m: #{wid.to_s(16)}; type=#{w.type.inspect}"
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
        p [:ignoring, w.inspect]
        w.stack
        return w
      end
      if w.desktop?
        w.floating = true
      end
      STDERR.puts "\e[35madopt5\e[0m: #{wid.to_s(16)}"
      attr = w.get_window_attributes
      if attr.wclass == 2 # InputOnly
        # We don't want to adopt inputonly windows, as they're
        # for event handling only
        return w
      end
      STDERR.puts "\e[35madopt4\e[0m: #{wid.to_s(16)}"
      return w if attr.override_redirect
      STDERR.puts "\e[35madopt9\e[0m: #{wid.to_s(16)}"
      STDERR.puts attr.inspect
      w.mapped = attr.map_state != 0
      STDERR.puts "\e[35madopt7\e[0m: #{wid.to_s(16)}"
      geom = w.get_geometry
      STDERR.puts "\e[35madopt8\e[0m: #{wid.to_s(16)}"
      return w if geom.is_a?(X11::Form::Error)
      STDERR.puts "adopt: #{wid.to_s(16)} 3"
    
      if geom.width < 2 || geom.height < 2 #|| (geom.x+geom.w) < 0 || (geom.y+geom.h) < 0
        return w
      end

      p [:adopt, wid]
      @windows[wid] = w

      wms = w.get_property(:_NET_WM_STATE, :atom)&.value
      if wms == dpy.atom(:_NET_WM_STATE_ABOVE)
        # This seems like it's probably not a good idea.
        p [:ignorin_raised]
        return w
      end

      if w.special?
        w.configure(border_width: 0)
      else
        w.configure(border_width: 1)
        w.change_attributes(values: {X11::Form::CWBorderPixel => @border_normal})
      end

      desktop = dpy.get_property(wid, :_NET_WM_DESKTOP, :cardinal)&.value
      desktop ||= current_desktop_id
      move_to_desktop(wid, desktop)
      w.select_input(
        X11::Form::FocusChangeMask     |
        X11::Form::PropertyChangeMask  |
        X11::Form::EnterWindowMask     |
        X11::Form::LeaveWindowMask
      )
    rescue Exception => e
      p [:ZZZZZZZZZZZZZZZZZZZZZZZZZADOPT_FAILED, e]
      # Failure here most likely reflects a window that has "disappeared".
      # We should handle that better, but for now this is fine
    end
    update_client_list
    return w
  end

  def map_window(wid)
    w = window(wid)
    attr = w.get_geometry
    return if attr.is_a?(X11::Form::Error)
    x = attr.x
    y = attr.y
    width  = attr.width
    height = attr.height
    width  = rootgeom.width / 2 if width < 10
    height = rootgeom.height - 100 if height < 10
        
    # FIXME: This is irrelevant if tiled layout, so maybe
    # Factor out into floating layout
    if x == 0
      x = (rootgeom.width - width)/2
    end
    if y == 0
      y = (rootgeom.height - height)/2
    end
    w.configure(x:, y:, width:, height:)
    w.map
    current_desktop.update_layout
    set_focus(wid) unless w.special?
  end

  def move_to_desktop(wid,desktop)
    return if wid == root_id
    d = desktops[desktop] || desktops[0]
    w = window(wid)
    old = w.desktop
    w.desktop = d
    d.update_layout if d.active?
    old&.update_layout
    d.active? ? w.show : w.hide
  end

  def change_desktop(d)
    if current_desktop_id == d
      # Allow using this as refresh, but reduce disruption
      current_desktop.update_layout
      return current_desktop.show
    end
    old = current_desktop
    @current_desktop_id = d
    current_desktop.show
    current_desktop.update_layout
    # FIXME: Switch focus (keep focus stack per desktop)
    old.hide
    change_property(:_NET_CURRENT_DESKTOP, :cardinal, d)
    f = current_desktop&.children&.find {|w| !w.special?}
    set_focus(f.wid) if f
  end


  def set_focus(wid)
    return if wid == root_id
    w = window(wid)
    p [:set_focus, wid, w]
    
    # FIXME: This may be a bit brutal, in that it prevents keyboard control of the desktop or dock.
    return if w.special?
    
    @focus&.change_attributes(values: {X11::Form::CWBorderPixel => @border_normal})
    @focus = w
    @focus.set_input_focus(:parent)
    @focus.change_attributes(values: {X11::Form::CWBorderPixel => @border_focus})
    p [:set_focus, wid, @focus, :children]
    change_property(:_NET_ACTIVE_WINDOW, :window, wid)
  end

  # FIXME: This needs tweaks. Especially for floating windows, where
  # what we really want is to e.g. treat partially overlapping windows
  # so that the one closest to *overlapping* the correct border is picked
  def find_closest(w, dir, from = windows.values)
    g = w.get_geometry

    case dir
    when :left  then predicate = ->(g2) { g.x  - (g2.x + g2.width)  }
    when :right then predicate = ->(g2) { g2.x - (g.x  + g.width)   }
    when :up    then predicate = ->(g2) { g.y  - (g2.y + g2.height) }
    when :down  then predicate = ->(g2) { g2.y - (g.y  + g.height)  }
    end

    min = 10000
    list = []
    p [:here]
    from.each do |win|
      next if win.special?
      next if !win.mapped
      p [:checking, win, dir]
      g2 = win.get_geometry rescue nil
      next if g2.nil?
      dist = predicate.call(g2).abs
      if dist <= min
        if dist == min
          list << win
        else
          list = [win]
          min = dist
        end
      end
      p [dist, min, list]
    end
    p [min, list]
    return nil if list.empty?
    return list.first if list.length == 1

    # More than one in the same direction,
    # FIXME: For now we just pick the first.
    # Ideally I'd probably want to request the pointer location
    # and find the closest along the other axis.
    # May also want to check which window had focus last,
    # and track last direction, so that e.g. left->right->left
    # will go back to the same window

    return list.first
  end

  def destroy_window(wid)
    if w = @windows[wid]
      @windows.delete(wid)
      current_desktop.update_layout
      update_client_list
    end
  end
  
  # # X Event-handlers

  def on_error(ev) = destroy_window(ev.bad_resource_id)

   # FIXME: Shouldn't most of these be dispatched to the *window*?
  def on_map_notify(ev)
    window(ev.window).mapped = true
    current_desktop.update_layout
  end

  def on_unmap_notify(ev)
    window(ev.window).mapped = false
    current_desktop.update_layout
  end

  def on_map_request(ev) = map_window(ev.window)

  def on_property_notify(ev)
    p dpy.get_atom_name(ev.atom) rescue nil
  end

  def on_focus_in(ev)       = (set_focus(ev.event) if !focus)
  def on_enter_notify(ev)   = set_focus(ev.event)
  def on_unmap_notify(ev)   = window(ev.window)&.desktop&.update_layout
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
    w = window(wid)
    p [:got_wm_state_for, w, prop1 == 0 ? "None" : dpy.get_atom_name(prop1),
      prop2 == 0 ? "None" : dpy.get_atom_name(prop2)]
    # FIXME: Need to check if "action" for toggle vs set/clear
    [prop1, prop2].each do |prop|
      case prop
      when dpy.atom(:_NET_WM_STATE_FULLSCREEN)
        w.toggle_maximize
      end
    end
    # For the time being, we recognize two things only:
    # NET_WM_STATE_FULLSCREEN and NET_WM_STATE_MAXIMIZED_{VERT,HORZ}
  end

  # FIXME: This should be _NET_CLOSE_WINDOW
  # and _NET_CLOSE_WINDOW should initiate a WM_DELETE_WINDOW
  # *to the client* if they support it, w/fallback to destroyf
  def on_net_wm_desktop(wid, d) = move_to_desktop(wid, d)

  def on_wm_delete_window(*args)
    # FIXME: Include id in args
    @focus.destroy if @focus
  end

  # # RWM specific ClientMessages

  # Move focus to the "nearest" window in `dir` direction
  def on_rwm_focus(_, dir)
    dir = dpy.get_atom_name(dir).downcase.to_sym
    return if !@focus || @focus.special?
    w = find_closest(@focus, dir, @focus.desktop.children)
    set_focus(w.wid) if w
  end

  # Toggle the direction of the node split.
  def on_rwm_shift_direction(_,dir)
    # FIXME: Respect the window passed instead of doing it to @focus
    return if !@focus || @focus.special?
    node = current_desktop&.layout&.find(@focus)
    if node
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
    node = current_desktop&.layout&.find(@focus)
    if node
      node = node.parent if node.is_a?(Leaf)
      tmp = node.nodes[0]
      node.nodes[0] = node.nodes[1]
      node.nodes[1] = tmp
      current_desktop&.update_layout
    end
  end

  # Move the focused window, either swapping it into the container
  # of the nearest leaf (if tiled), or moving it stepwise if floating
  def on_rwm_move(_,dir)
    dir = dpy.get_atom_name(dir).downcase.to_sym
    p [:on_rwm_move, dir]
    return if !@focus || @focus.special?

    if @focus.floating?
      # FIXME:
      # Move stepwise instead.
      g = @focus.get_geometry rescue nil
      return if g.nil?
      case dir
      when :left  then @focus.configure(x: g.x - 20)
      when :right then @focus.configure(x: g.x + 20)
      when :down  then @focus.configure(y: g.y + 20)
      when :up    then @focus.configure(y: g.y - 20)
      end
      return
    end

    w = find_closest(@focus, dir, @focus.desktop.children.find_all{_1.mapped})

    l1 = @focus.desktop&.layout&.find(@focus)
    l2 = w&.desktop&.layout&.find(w)
    p [l1,l2]
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
      set_focus(@focus.wid)
    end
  end

end
