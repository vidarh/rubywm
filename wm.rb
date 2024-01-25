
require_relative 'floating'

class WindowManager
  attr_reader :dpy, :desktops, :windows, :focus

  def inspect = "<WindowManager>"

  def initialize dpy, config
    @dpy = dpy
    @windows = {}

    @border_normal = 0x88666666
    @border_focus  = 0xffff66ff

    @floating = FloatingLayout.new(rootgeom)

    process_config(config)
    
    change_property(:_NET_NUMBER_OF_DESKTOPS, :cardinal, @desktops.count)

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

  # FIXME: I'm not particlarly happy about building this in.
  # I prefer the bspwm approach of externalising it, because
  # I need/want an API to change it dynamically anyway, so
  # this is likely to change.
  def process_config(config)
    num_desktops = config.dig(:desktops, :number) || 10
    @desktops ||= num_desktops.times.map do |num|
      c = config.dig(:desktops, num+1)
      name = c&.dig(:name) || (num+1).to_s
      Desktop.new(self, num, name).tap do |d|
        if c&.dig(:layout) == "floating"
          # FIXME: Should be ok to set this to @floating
          # but some logic checks for a nil layout
          d.layout = nil
        else
          d.layout = TiledLayout.new(d, rootgeom)
          process_node_config(d.layout.root,c)
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
  def root               = (@root ||= X11::Window.new(@dpy, root_id))
  def layout = current_desktop&.layout || @floating
  def layout_for(w) = (w.floating? ? @floating : layout)
  def update_layout = layout.call(@focus)

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
    w = @windows[wid] # To avoid infinite recursion, this *must not* use #window
    return w if w
    w = Window.new(self, wid)
    begin
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
      attr = w.get_window_attributes
      return w if attr.wclass == 2 # InputOnly
      return w if attr.override_redirect
      w.mapped = attr.map_state != 0
      geom = w.get_geometry
      return w if geom.is_a?(X11::Form::Error) || geom.width < 2 || geom.height < 2
      @windows[wid] = w

      wms = w.get_property(:_NET_WM_STATE, :atom)&.value
      if wms == dpy.atom(:_NET_WM_STATE_ABOVE)
        # This seems like it's probably not a good idea.
        return w
      end

      w.set_border(@border_normal)

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
    w.mapped = true
    layout_for(w).place(w, @focus) unless layout_for(w).find(w)
    w.map
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
      update_layout
      return current_desktop.show
    end
    old = current_desktop
    @current_desktop_id = d
    current_desktop.show
    update_layout
    # FIXME: Switch focus (keep focus stack per desktop)
    old.hide
    change_property(:_NET_CURRENT_DESKTOP, :cardinal, d)
    f = current_desktop&.mapped_regular_children&.first
    set_focus(f.wid) if f
  end


  def set_focus(wid)
    return if wid == root_id
    w = window(wid)
    
    # FIXME: This may be a bit brutal, in that it prevents keyboard control of the desktop or dock.
    return if w.special?
    
    @focus&.set_border(@border_normal)
    @focus = w
    @focus.set_input_focus(:parent)
    @focus.set_border(@border_focus)
    change_property(:_NET_ACTIVE_WINDOW, :window, wid)
  end

  def destroy_window(wid)
    if w = @windows[wid]
      @windows.delete(wid)
      update_layout
      update_client_list
    end
  end
  
  # # X Event-handlers

  def on_error(ev) = destroy_window(ev.bad_resource_id)

  def on_map_notify(ev)      = (window(ev.window).mapped = true)
  def on_unmap_notify(ev)    = (window(ev.window).mapped = false)
  def on_map_request(ev)     = map_window(ev.window)
  def on_property_notify(ev) = (p dpy.get_atom_name(ev.atom) rescue nil)

  def on_button_press(ev)
    return if !ev.child
    w = window(ev.child)
    @attr = w.get_geometry rescue nil
    if @attr
      set_focus(w.wid)
      @start = ev
    end
  end

  def on_motion_notify(ev)
    # @start.button == 1 -> move
    # @start.button == 3 -> resize
    if ev.child != @start.child
      set_focus(ev.child) rescue nil # FIXME
    end
    return if !@start&.child || !@attr

    xdiff = ev.root_x - @start.root_x;
    ydiff = ev.root_y - @start.root_y;

    w = window(@start.child)

    # FIXME: Any other types we don't want to allow moving or resizing
    begin
      return if w.special?
    rescue # FIXME: Why is this here?
    end

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
