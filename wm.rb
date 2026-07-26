
require_relative 'floating'
require_relative 'monitor'
require_relative 'desktop_navigation'
require 'json'

class WindowManager
  attr_reader :dpy, :desktops, :windows, :focus, :monitors

  class OwnershipError < StandardError; end

  UINT32_MAX = 0xffffffff
  DESKTOP_PROTOCOL_VERSION = 1
  REMOVE_FORCE = 1 << 0
  ROOT_EVENT_MASK = (
    X11::Form::SubstructureNotifyMask |
    X11::Form::SubstructureRedirectMask |
    X11::Form::StructureNotifyMask |
    X11::Form::EnterWindowMask |
    X11::Form::LeaveWindowMask |
    X11::Form::ButtonPressMask |
    X11::Form::ExposureMask |
    X11::Form::KeyPressMask |
    X11::Form::FocusChangeMask
  ).freeze

  def inspect = "<WindowManager>"

  def initialize dpy, config
    @dpy = dpy
    @windows = {}
    @monitors = []
    @startup_packets = []
    claim_window_manager!
    snapshot = read_desktop_snapshot
    @desktop_generation = snapshot&.dig(:generation).to_i

    @border_normal = 0x88666666
    @border_focus  = 0xffff66ff

    process_config(config, snapshot)

    mask = X11::Form::ButtonPressMask|X11::Form::ButtonReleaseMask|X11::Form::PointerMotionMask
    # Grab Super+button1/3 (move/resize), ignoring the lock modifiers
    # (NumLock=Mod2, CapsLock=Lock) by grabbing every combination of them.
    lock_combos = [0, X11::Form::Mod2, X11::Form::Lock, X11::Form::Mod2|X11::Form::Lock]
    [1, 3].each do |button|
      lock_combos.each do |lock|
        root.grab_button(true, mask, :async, :async, 0, 0, button, X11::Form::Mod4|lock)
      end
    end

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
     @desktop_state_ready = true
     publish_desktop_state
  end

  # SubstructureRedirectMask may only be selected by one X client. pure-x11
  # queues errors from void requests asynchronously, so follow the selection
  # with a synchronous request, then inspect the packets that preceded its
  # reply. Without this barrier a second RubyWM can appear to start, overwrite
  # EWMH state, and still leave the old process handling all WM commands.
  def claim_window_manager!
    root.select_input(ROOT_EVENT_MASK)
    @dpy.get_input_focus

    queued = []
    queued << @dpy.next_packet while @dpy.peek_packet
    ownership_error = queued.find do |packet|
      packet.is_a?(X11::Form::Error) &&
        packet.code == 10 && # BadAccess
        packet.major_opcode == 2 && # ChangeWindowAttributes
        packet.bad_resource_id == root_id
    end
    if ownership_error
      raise OwnershipError,
            "another window manager already owns display #{ENV.fetch("DISPLAY", ":0")}"
    end

    protocol_error = queued.find { _1.is_a?(X11::Form::Error) }
    raise X11::Error.new(protocol_error) if protocol_error
    @startup_packets.concat(queued)
  end

  def next_packet
    @startup_packets.empty? ? @dpy.next_packet : @startup_packets.shift
  end

  # Publish which desktop hosts desktop-type windows (config `desktop: true`),
  # as a custom _RWM_DESKTOP_WINDOW_DESKTOP cardinal on the root, so the desktop
  # client (Dwin) reads it instead of hardcoding a desktop number.
  def publish_desktop_window_host
    return unless @desktop_window_desktop
    change_property(:_RWM_DESKTOP_WINDOW_DESKTOP, :cardinal,
                    @desktop_window_desktop.id)
  end

  def publish_utf8_list(atom, values)
    bytes = (values.map { _1.to_s }.join("\0") + "\0").bytes
    root.change_property(:replace, atom, dpy.atom(:UTF8_STRING), 8, bytes)
  rescue X11::Error => e
    $logger.debug { "error publishing #{atom}: #{e.message}" }
  end

  # Publish the standard EWMH view and the aligned RubyWM metadata arrays as one
  # logical snapshot. _RWM_DESKTOP_GENERATION is written last so readers can
  # detect an update that crossed multiple X properties.
  def publish_desktop_state
    change_property(:_NET_NUMBER_OF_DESKTOPS, :cardinal, @desktops.length)
    publish_utf8_list(:_NET_DESKTOP_NAMES, @desktops.map(&:name))
    current = @desktops[@current_desktop_id] ||
              @primary_monitor&.active_desktop || @desktops.first
    @current_desktop_id = current&.id || 0
    change_property(:_NET_CURRENT_DESKTOP, :cardinal, @current_desktop_id)
    @monitors.each do |monitor|
      next unless monitor.active_desktop
      change_property("_NET_CURRENT_DESKTOP_MONITOR_#{monitor.id}".to_sym,
                      :cardinal, monitor.active_desktop.id)
    end

    geom = rootgeom
    change_property(:_NET_DESKTOP_GEOMETRY, :cardinal,
                    [geom.width, geom.height])
    change_property(:_NET_DESKTOP_VIEWPORT, :cardinal,
                    [0, 0] * @desktops.length)
    publish_workarea

    publish_utf8_list(:_RWM_DESKTOP_KEYS, @desktops.map(&:key))
    publish_utf8_list(:_RWM_DESKTOP_PROJECTS,
                      @desktops.map { _1.project || "" })
    publish_utf8_list(:_RWM_DESKTOP_GROUPS,
                      @desktops.map { _1.group || "" })
    change_property(:_RWM_DESKTOP_MODES, :cardinal,
                    @desktops.map(&:mode_code))
    change_property(:_RWM_DESKTOP_FLAGS, :cardinal,
                    @desktops.map(&:flags))
    change_property(:_RWM_DESKTOP_CLIENT_COUNTS, :cardinal,
                    desktop_client_counts)
    publish_desktop_window_host
    publish_visible_desktops
    publish_desktop_history
    publish_desktop_generation
  end

  def desktop_client_counts
    @desktops.map { |desktop| desktop.children.length }
  end

  # Occupancy changes independently of desktop metadata when clients are
  # opened, closed, or moved. Publish the aligned counts first and generation
  # last so Rebar can update without polling every client window.
  def publish_desktop_occupancy
    return unless @desktop_state_ready
    change_property(:_RWM_DESKTOP_CLIENT_COUNTS, :cardinal,
                    desktop_client_counts)
    publish_desktop_generation
  end

  def publish_visible_desktops
    change_property(:_RWM_VISIBLE_DESKTOPS, :cardinal,
                    @monitors.map { _1.active_desktop&.id || UINT32_MAX })
  end

  def publish_desktop_generation
    @desktop_generation = (@desktop_generation.to_i + 1) & UINT32_MAX
    change_property(:_RWM_DESKTOP_GENERATION, :cardinal,
                    @desktop_generation)
  end

  # EWMH hints we actually honour. Advertised via _NET_SUPPORTED so toolkits
  # (and pagers/wmctrl) know an EWMH-compliant WM is running.
  SUPPORTED_HINTS = %i[
    _NET_SUPPORTING_WM_CHECK _NET_SUPPORTED
    _NET_NUMBER_OF_DESKTOPS _NET_CURRENT_DESKTOP
    _NET_ACTIVE_WINDOW _NET_CLIENT_LIST _NET_CLOSE_WINDOW
    _NET_WM_DESKTOP _NET_WM_STATE _NET_WM_STATE_FULLSCREEN
    _NET_WM_STATE_MAXIMIZED_VERT _NET_WM_STATE_MAXIMIZED_HORZ
    _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DESKTOP
    _NET_WM_WINDOW_TYPE_DOCK _NET_WM_WINDOW_TYPE_DIALOG
    _NET_WM_STRUT _NET_WM_STRUT_PARTIAL _NET_WORKAREA
    _NET_CLIENT_LIST_STACKING _NET_DESKTOP_NAMES
    _NET_DESKTOP_GEOMETRY _NET_DESKTOP_VIEWPORT
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
    @dpy.change_property(:replace, @check_window, :_NET_WM_NAME, dpy.atom(:UTF8_STRING), 8, "rubywm".bytes)
    change_property(:_NET_SUPPORTED, :atom, SUPPORTED_HINTS.map { dpy.atom(_1) })
  rescue => e
    $logger.error("setup_ewmh failed: #{e.class}: #{e.message}")
  end

  def set_current_desktop(desktop, monitor = active_monitor)
    @current_desktop_id = desktop
    change_property(:_NET_CURRENT_DESKTOP, :cardinal, desktop)
    if monitor
      change_property("_NET_CURRENT_DESKTOP_MONITOR_#{monitor.id}".to_sym,
                      :cardinal, desktop)
    end
    publish_visible_desktops
    publish_desktop_history
    publish_desktop_generation
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
  def root_cardinals(atom, length: 1024)
    value = @dpy.get_property(root_id, atom, :cardinal,
                              length: length)&.value
    value.nil? ? [] : Array(value)
  rescue X11::Error
    []
  end

  def root_utf8_list(atom)
    value = @dpy.get_property(root_id, atom, dpy.atom(:UTF8_STRING),
                              length: 16_384)&.value
    return [] if value.nil?
    values = value.to_s.split("\0", -1)
    values.pop if values.last == ""
    values
  rescue X11::Error
    []
  end

  # A RubyWM-owned root snapshot survives a WM restart because X properties
  # live on the server. Existing clients keep their numeric EWMH assignments,
  # while stable keys and metadata are reconstructed before they are adopted.
  def read_desktop_snapshot
    generation = root_cardinals(:_RWM_DESKTOP_GENERATION, length: 1).first
    count = root_cardinals(:_NET_NUMBER_OF_DESKTOPS, length: 1).first.to_i
    return if generation.nil? || count < 1 || count > 256

    keys = root_utf8_list(:_RWM_DESKTOP_KEYS)
    names = root_utf8_list(:_NET_DESKTOP_NAMES)
    projects = root_utf8_list(:_RWM_DESKTOP_PROJECTS)
    groups = root_utf8_list(:_RWM_DESKTOP_GROUPS)
    modes = root_cardinals(:_RWM_DESKTOP_MODES)
    flags = root_cardinals(:_RWM_DESKTOP_FLAGS)
    return unless [keys, names, projects, groups, modes, flags].all? {
      _1.length == count
    }
    return if keys.any?(&:empty?) || keys.uniq.length != count

    records = count.times.map do |id|
      {
        key: keys[id],
        name: names[id],
        project: projects[id].empty? ? nil : projects[id],
        group: groups[id].empty? ? nil : groups[id],
        mode: Desktop::MODE_CODES.key(modes[id]) || :tiled,
        flags: flags[id].to_i,
      }
    end
    {
      generation: generation,
      records: records,
      visible: root_cardinals(:_RWM_VISIBLE_DESKTOPS,
                              length: 256),
      history: root_cardinals(:_RWM_DESKTOP_HISTORY,
                              length: 65_536),
    }
  rescue X11::Error => e
    $logger.debug { "error reading desktop snapshot: #{e.message}" }
    nil
  end

  def configured_desktop_records(config)
    count = config.dig(:desktops, :number) || 10
    count.times.map do |num|
      desktop_config = config.fetch(:desktops, {})
      configured = desktop_config.key?(num + 1)
      c = desktop_config[num + 1] || {}
      flags = if configured
        Desktop::FLAG_STATIC
      else
        Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE
      end
      flags |= Desktop::FLAG_PINNED if c[:pinned]
      flags |= Desktop::FLAG_GROUP_ROOT if c[:group_root]
      if c[:desktop]
        flags |= Desktop::FLAG_DESKTOP_WINDOW | Desktop::FLAG_PINNED
      end
      {
        key: (c[:key] || "desktop-#{num + 1}").to_s,
        name: (c[:name] || (num + 1).to_s).to_s,
        project: c[:project]&.to_s,
        group: c[:group]&.to_s,
        mode: c[:layout] == "floating" ? :floating : :tiled,
        flags: flags,
        config: c,
      }
    end
  end

  def merge_desktop_records(configured, snapshot)
    return configured unless snapshot

    snapshot_records = snapshot[:records].map(&:dup)
    records = configured.each_with_index.map do |configured_record, index|
      prior = snapshot_records[index]

      if configured_record[:flags] & Desktop::FLAG_STATIC != 0
        # Explicit numbered configuration owns its numeric slot. Configuration
        # remains authoritative for its identity, mode, flags, and layout.
        configured_record
      elsif prior &&
            prior[:flags] & Desktop::FLAG_SLOT_BACKED != 0
        # A placeholder or project lease remains at the same keyboard address.
        prior.merge(config: configured_record[:config])
      else
        # Upgrade snapshots from before slot flags existed to the new implicit
        # placeholder model instead of treating all ten initial slots as static.
        configured_record
      end
    end

    # Snapshot records beyond the configured compatibility pool are genuine
    # appended dynamic desktops. Keep them in their existing EWMH order.
    records.concat(snapshot_records.drop(configured.length))
    records
  end

  # Before the group-aware allocator existed, every project leased an initial
  # numeric slot. That made secondary projects steal independent Super+n
  # addresses. Keep one numeric address per group and move every additional
  # slot-backed child to the overflow tail, restoring its numeric placeholder.
  def normalize_group_child_leases(records, configured)
    normalized = records.map(&:dup)
    by_group = Hash.new { |hash, key| hash[key] = [] }
    normalized.each_with_index do |record, index|
      group = record[:group].to_s.strip
      next if group.empty? || index >= configured.length
      next if record[:flags].to_i & Desktop::FLAG_AVAILABLE != 0
      by_group[group] << [index, record]
    end

    move_indices = by_group.values.flat_map do |entries|
      root = entries.find {
        _2[:flags].to_i & Desktop::FLAG_GROUP_ROOT != 0
      }
      configured_entry = entries.find {
        _2[:flags].to_i & Desktop::FLAG_STATIC != 0
      }
      keep_index = (root || configured_entry || entries.first)&.first
      entries.filter_map do |index, record|
        next if index == keep_index
        index if record[:flags].to_i & Desktop::FLAG_SLOT_BACKED != 0
      end
    end.sort

    remap = {}
    moved = move_indices.map do |index|
      record = normalized[index].dup
      record[:flags] &= ~(Desktop::FLAG_SLOT_BACKED |
                          Desktop::FLAG_AVAILABLE)
      record[:config] = nil
      remap[index] = normalized.length + remap.length
      normalized[index] = configured[index].dup
      record
    end
    [normalized.concat(moved), remap]
  end

  def process_config(config, snapshot = nil)
    process_monitors

    # FIXME: Move to each monitor.
    @floating = FloatingLayout.new(self)

    configured = configured_desktop_records(config)
    @initial_desktop_count = configured.length
    records = merge_desktop_records(configured, snapshot)
    records, @desktop_index_remap =
      normalize_group_child_leases(records, configured)
    keys = records.map { _1[:key] }
    raise ArgumentError, "desktop keys must be unique" if keys.uniq != keys
    @desktops = records.each_with_index.map do |record, id|
      Desktop.new(self, id, record[:name],
                  key: record[:key],
                  project: record[:project],
                  group: record[:group],
                  mode: record[:mode],
                  flags: record[:flags])
    end

    visible = snapshot&.dig(:visible) || []
    used = []
    @monitors.each_with_index do |monitor, monitor_id|
      requested = visible[monitor_id]
      requested = @desktop_index_remap.fetch(requested, requested) if requested
      desktop = @desktops[requested] if requested && requested != UINT32_MAX
      desktop = nil if desktop && used.include?(desktop)
      desktop ||= @desktops.find { !used.include?(_1) }
      monitor.active_desktop = desktop
      used << desktop if desktop
    end
    restore_desktop_history(snapshot)

    @desktops.each_with_index do |desktop, id|
      record = records[id]
      @desktop_window_desktop = desktop if desktop.desktop_window?
      next if desktop.mode == :floating

      desktop.layout = TiledLayout.new(desktop, desktop.geometry)
      process_node_config(desktop.layout.root, record[:config])
    end
  end

  # History is held as Desktop objects, so explicit renumbering preserves it.
  # On the root it is a fixed-width MRU row per monitor, padded with UINT32_MAX.
  def restore_desktop_history(snapshot)
    old_count = snapshot&.dig(:records)&.length.to_i
    raw = snapshot&.dig(:history) || []
    @desktop_history = @monitors.each_with_index.map do |monitor, monitor_id|
      restored = if old_count.positive?
        raw.slice(monitor_id * old_count, old_count).to_a.filter_map do |id|
          next if id == UINT32_MAX
          @desktops[(@desktop_index_remap || {}).fetch(id, id)]
        end
      else
        []
      end
      restored = restored.select { @desktops.include?(_1) }.uniq
      active = monitor.active_desktop
      active ? [active, *restored.reject { _1 == active }] : restored
    end
  end

  def remember_desktop(monitor, desktop)
    return unless monitor && desktop
    history = (@desktop_history[monitor.id] ||= [])
    history.delete(desktop)
    history.unshift(desktop)
  end

  def forget_desktop(desktop)
    @desktop_history&.each { _1.delete(desktop) }
  end

  def desktop_history_indices
    count = @desktops.length
    @monitors.flat_map do |monitor|
      history = Array(@desktop_history[monitor.id])
                  .select { @desktops.include?(_1) }
                  .uniq
                  .first(count)
                  .map(&:id)
      history + Array.new(count - history.length, UINT32_MAX)
    end
  end

  def publish_desktop_history
    change_property(:_RWM_DESKTOP_HISTORY, :cardinal,
                    desktop_history_indices)
  end

  def desktop_navigation_for(monitor)
    rows = @desktops.map do |desktop|
      {
        index: desktop.id,
        key: desktop.key,
        name: desktop.name,
        project: desktop.project,
        group: desktop.group,
        mode: desktop.mode,
        flags: desktop.flags,
        occupied: !desktop.children.empty?,
      }
    end
    history = Array(@desktop_history[monitor.id]).map(&:id)
    DesktopNavigation.new(
      rows,
      current: monitor.active_desktop&.id,
      history: history,
    )
  end

  def desktop_for_group_address(address, monitor)
    desktop_navigation_for(monitor).group_target(address)
  end

  def append_desktop(key:, name:, project: nil, group: nil, mode: :tiled,
                     flags: 0, publish: true)
    raise ArgumentError, "desktop key is already in use" if @desktops.any? {
      _1.key == key
    }

    desktop = Desktop.new(self, @desktops.length, name,
                          key: key, project: project, group: group,
                          mode: mode, flags: flags)
    if mode == :tiled
      desktop.layout = TiledLayout.new(desktop, desktop.geometry)
    end
    @desktops << desktop
    publish_desktop_state if publish
    desktop
  end

  # Rebar's top-bar "+" needs no naming policy or filesystem access. It asks
  # RubyWM for one temporary empty view in the current group; the user can then
  # re-key and describe that active view through `rwmctl edit current`.
  def add_group_view(monitor)
    source = monitor&.active_desktop
    raise ArgumentError, "monitor does not exist" unless source
    group = source.group.to_s.strip
    raise ArgumentError, "current desktop has no group" if group.empty?

    desktop = append_desktop(
      key: next_automatic_desktop_key,
      name: "New view",
      project: source.project,
      group: group,
      mode: :tiled,
    )
    change_desktop_on_monitor(monitor, desktop)
    desktop
  end

  def reusable_desktop(excluding: nil)
    @desktops.find do |desktop|
      next if desktop == excluding
      desktop.available_placeholder? &&
        !desktop.static? &&
        !desktop.pinned? &&
        !desktop.desktop_window? &&
        !desktop.active? &&
        desktop.children.empty?
    end
  end

  def reset_available_desktop(desktop, id)
    forget_desktop(desktop)
    desktop.id = id
    desktop.key = "desktop-#{id + 1}"
    desktop.name = (id + 1).to_s
    desktop.project = nil
    desktop.group = nil
    desktop.mode = :tiled
    desktop.flags = Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE
    desktop.layout = TiledLayout.new(desktop, desktop.geometry)
    desktop
  end

  def trim_trailing_available_desktops
    minimum = @initial_desktop_count || 1
    while @desktops.length > minimum
      desktop = @desktops.last
      break unless desktop.available_placeholder? &&
                   !desktop.active? &&
                   desktop.children.empty?
      forget_desktop(desktop)
      @desktops.pop
    end
  end

  # Move a dynamic desktop into an existing reusable slot without recreating
  # its windows or layout. Desktop and monitor references point to the Desktop
  # object, so changing that object's EWMH id moves the complete view atomically.
  def move_desktop(source_index, target_index: nil, publish: true)
    source = @desktops[source_index]
    return { ok: false, error: "desktop does not exist" } unless source
    if source.static? || source.pinned? || source.desktop_window?
      return { ok: false, error: "configured or pinned desktops cannot be renumbered" }
    end
    if source.available_placeholder?
      return { ok: false, error: "source desktop is an empty placeholder" }
    end

    target = target_index.nil? ? reusable_desktop(excluding: source) :
                                 @desktops[target_index]
    return { ok: false, error: "no reusable desktop slot is available" } unless target
    unless target.available_placeholder? &&
           !target.static? &&
           !target.pinned? &&
           !target.desktop_window? &&
           !target.active? &&
           target.children.empty?
      return { ok: false, error: "target desktop is not an empty reusable slot" }
    end
    return { ok: false, error: "source and target are the same desktop" } if
      source == target

    old_index = source.id
    new_index = target.id
    if new_index < (@initial_desktop_count || 0) &&
       group_has_numeric_address?(source.group, excluding: source)
      return {
        ok: false,
        error: "group already has a numeric desktop address",
      }
    end

    @desktops[new_index] = source
    @desktops[old_index] = target

    source.id = new_index
    source.flags &= ~(Desktop::FLAG_STATIC | Desktop::FLAG_AVAILABLE)
    source.flags |= Desktop::FLAG_SLOT_BACKED
    reset_available_desktop(target, old_index)
    trim_trailing_available_desktops
    @desktops.each_with_index { |desktop, id| desktop.id = id }

    @windows.each_value(&:publish_desktop)
    monitor = source.monitor
    point_layout_at(source, monitor) if monitor
    current = active_monitor&.active_desktop || @primary_monitor&.active_desktop
    @current_desktop_id = current&.id || 0
    publish_desktop_state if publish
    {
      ok: true,
      key: source.key,
      from: old_index,
      desktop: source.id,
      number: source.id + 1,
      count: @desktops.length,
    }
  end

  def lease_desktop(desktop, key:, name:, project:, group:, mode:, flags:)
    desktop.key = key
    desktop.name = name
    desktop.project = project
    desktop.group = group
    desktop.mode = mode
    desktop.flags = Desktop::FLAG_SLOT_BACKED | flags
    desktop.layout = if mode == :tiled
      TiledLayout.new(desktop, desktop.geometry)
    end
    desktop
  end

  def group_already_addressed?(group, excluding: nil)
    group = group.to_s.strip
    return false if group.empty?
    @desktops.any? do |desktop|
      desktop != excluding &&
        !desktop.available_placeholder? &&
        desktop.group.to_s.strip == group
    end
  end

  def group_has_numeric_address?(group, excluding: nil)
    group = group.to_s.strip
    return false if group.empty?
    @desktops.first(@initial_desktop_count).any? do |desktop|
      desktop != excluding &&
        !desktop.available_placeholder? &&
        desktop.group.to_s.strip == group
    end
  end

  def secondary_group_slot?(desktop)
    return false unless desktop.slot_backed?
    return false unless desktop.id < (@initial_desktop_count || 0)
    group = desktop.group.to_s.strip
    return false if group.empty?
    peers = @desktops.first(@initial_desktop_count).select do |candidate|
      !candidate.available_placeholder? &&
        candidate.group.to_s.strip == group
    end
    keep = peers.find(&:group_root?) ||
           peers.find(&:static?) ||
           peers.min_by(&:id)
    keep && keep != desktop
  end

  # Move a secondary project out of the fixed numeric pool while keeping the
  # Desktop object itself. Windows, monitor ownership, layout, and MRU history
  # therefore follow it; the vacated number becomes an ordinary empty desktop.
  def rehome_group_child_to_tail(desktop, publish: true)
    raise ArgumentError, "desktop limit reached" if @desktops.length >= 256
    old_index = desktop.id
    base_key = "desktop-#{old_index + 1}"
    desktop.key = next_automatic_desktop_key if desktop.key == base_key
    placeholder = Desktop.new(
      self,
      old_index,
      (old_index + 1).to_s,
      key: base_key,
      mode: :tiled,
      flags: Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE,
    )
    placeholder.layout = TiledLayout.new(placeholder, placeholder.geometry)
    @desktops[old_index] = placeholder
    desktop.id = @desktops.length
    desktop.flags &= ~(Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE)
    @desktops << desktop
    @windows.each_value(&:publish_desktop)

    monitor = desktop.monitor
    point_layout_at(desktop, monitor) if monitor
    current = active_monitor&.active_desktop ||
              @primary_monitor&.active_desktop
    @current_desktop_id = current&.id || 0
    publish_desktop_state if publish
    desktop
  end

  def next_automatic_desktop_key
    serials = @desktops.filter_map do |desktop|
      desktop.key[/\Adesktop-(\d+)\z/, 1]&.to_i
    end
    serial = [serials.max.to_i + 1, @desktops.length + 1].max
    serial += 1 while @desktops.any? { _1.key == "desktop-#{serial}" }
    "desktop-#{serial}"
  end

  # Idempotently resolve a stable project key to an EWMH desktop index.
  def ensure_desktop(spec)
    key = validated_desktop_key(spec["key"])

    mode_name = (spec["mode"] || "tiled").to_s
    unless %w[tiled floating].include?(mode_name)
      raise ArgumentError, "mode must be tiled or floating"
    end
    mode = mode_name.to_sym

    if desktop = @desktops.find { _1.key == key }
      if spec.key?("group") && spec.key?("rename_group")
        raise ArgumentError, "group assignment and group re-key cannot be combined"
      end

      new_key = if spec.key?("new_key")
        validated_desktop_key(spec["new_key"], field: "new desktop key")
      else
        desktop.key
      end
      if new_key != desktop.key &&
         @desktops.any? { _1 != desktop && _1.key == new_key }
        raise ArgumentError, "desktop key is already in use: #{new_key}"
      end

      if spec.key?("mode") && desktop.mode != mode
        unless desktop.children.empty?
          raise ArgumentError, "a non-empty desktop's mode cannot be changed"
        end
      end

      metadata = {
        "name" => [:name, 512],
        "project" => [:project, 4096],
        "group" => [:group, 512],
      }.filter_map do |field, (attribute, limit)|
        next unless spec.key?(field)
        value = desktop_metadata_string(spec[field], field, limit)
        raise ArgumentError, "name cannot be empty" if field == "name" &&
          (value.nil? || value.empty?)
        [attribute, value]
      end

      new_group = nil
      group_members = []
      if spec.key?("rename_group")
        new_group = desktop_metadata_string(
          spec["rename_group"], "group", 512
        ).to_s.strip
        raise ArgumentError, "new group key cannot be empty" if new_group.empty?
        old_group = desktop.group.to_s.strip
        if !old_group.empty? && old_group != new_group
          group_members = @desktops.select {
            _1.group.to_s.strip == old_group
          }
          if @desktops.any? {
            !group_members.include?(_1) && _1.group.to_s.strip == new_group
          }
            raise ArgumentError, "group key is already in use: #{new_group}"
          end
        end
      end

      changed = false
      if new_key != desktop.key
        desktop.key = new_key
        changed = true
      end
      if spec.key?("mode") && desktop.mode != mode
        desktop.mode = mode
        desktop.layout = mode == :tiled ?
          TiledLayout.new(desktop, desktop.geometry) : nil
        changed = true
      end
      metadata.each do |attribute, value|
        next if desktop.public_send(attribute) == value
        desktop.public_send("#{attribute}=", value)
        changed = true
      end
      if new_group
        targets = group_members.empty? ? [desktop] : group_members
        targets.each do |member|
          next if member.group.to_s.strip == new_group
          member.group = new_group
          changed = true
        end
      end
      if spec["pinned"] && !desktop.pinned?
        desktop.flags |= Desktop::FLAG_PINNED
        changed = true
      end
      if changed && desktop.available_placeholder?
        desktop.flags &= ~Desktop::FLAG_AVAILABLE
      end
      if secondary_group_slot?(desktop)
        rehome_group_child_to_tail(desktop, publish: false)
        changed = true
      end
      publish_desktop_state if changed
      return {
        ok: true,
        desktop: desktop.id,
        key: desktop.key,
        created: false,
        updated: changed,
      }
    end
    if spec["update_only"]
      raise ArgumentError, "desktop key does not exist: #{key}"
    end
    raise ArgumentError, "desktop limit reached" if @desktops.length >= 256

    name = desktop_metadata_string(spec["name"] || key, "name", 512)
    raise ArgumentError, "name cannot be empty" if name.empty?
    project = desktop_metadata_string(spec["project"], "project", 4096)
    group = desktop_metadata_string(spec["group"], "group", 512)
    flags = spec["pinned"] ? Desktop::FLAG_PINNED : 0
    candidate = reusable_desktop unless group_already_addressed?(group)
    desktop = if candidate
      lease_desktop(
        candidate,
        key: key,
        name: name,
        project: project,
        group: group,
        mode: mode,
        flags: flags,
      ).tap { publish_desktop_state }
    else
      append_desktop(
        key: key,
        name: name,
        project: project,
        group: group,
        mode: mode,
        flags: flags,
      )
    end
    {
      ok: true,
      desktop: desktop.id,
      key: key,
      created: true,
      leased: desktop.slot_backed?,
    }
  end

  def validated_desktop_key(value, field: "desktop key")
    value = value.to_s
    raise ArgumentError, "#{field} is required" if value.empty?
    raise ArgumentError, "#{field} contains a NUL" if value.include?("\0")
    raise ArgumentError, "#{field} is too long" if value.bytesize > 512
    value
  end

  def desktop_metadata_string(value, field, limit)
    return if value.nil?
    value = value.to_s
    raise ArgumentError, "#{field} contains a NUL" if value.include?("\0")
    raise ArgumentError, "#{field} is too long" if value.bytesize > limit
    value
  end

  def replacement_desktop_for(target, preferred, occupied)
    candidates = [preferred, *@desktops].compact.uniq
    candidates.find { _1 != target && !occupied.include?(_1) }
  end

  # Remove a desktop, optionally moving its clients to a fallback first.
  # Configured/pinned desktops and non-empty desktops are protected unless the
  # caller explicitly forces removal.
  def remove_desktop(index, force: false, fallback_index: nil, publish: true)
    target = @desktops[index]
    return { ok: false, error: "desktop does not exist" } unless target
    if !target.slot_backed? && @desktops.length <= @monitors.length
      return { ok: false, error: "one visible desktop per monitor is required" }
    end
    if !force && (target.static? || target.pinned?)
      return { ok: false, error: "desktop is configured or pinned" }
    end
    if !force && target.active?
      return { ok: false, error: "desktop is visible" }
    end
    if target.slot_backed?
      base_key = "desktop-#{target.id + 1}"
      if @desktops.any? { _1 != target && _1.key == base_key }
        return { ok: false, error: "base desktop key is already in use" }
      end
    end

    children = target.children
    if !force && !children.empty?
      return { ok: false, error: "desktop is not empty" }
    end

    if fallback_index && !@desktops[fallback_index]
      return { ok: false, error: "fallback desktop does not exist" }
    end
    fallback = @desktops[fallback_index] if fallback_index
    fallback = nil if fallback == target
    if !children.empty? || target.active? || !target.slot_backed?
      fallback ||= @desktops[index.zero? ? 1 : index - 1]
      return { ok: false, error: "no fallback desktop" } unless fallback
    end

    children.dup.each { move_to_desktop(_1.wid, fallback.id) }

    affected = @monitors.select { _1.active_desktop == target }
    occupied = @monitors.reject { affected.include?(_1) }
                        .map(&:active_desktop).compact
    target.hide
    affected.each do |monitor|
      replacement = replacement_desktop_for(target, fallback, occupied)
      return { ok: false, error: "no unused replacement desktop" } unless replacement
      monitor.active_desktop = replacement
      remember_desktop(monitor, replacement)
      occupied << replacement
      point_layout_at(replacement, monitor)
      replacement.show
    end

    removed_id = target.id
    removed_key = target.key
    released = target.slot_backed?
    forget_desktop(target)
    if released
      base_key = "desktop-#{target.id + 1}"
      target.key = base_key
      target.name = (target.id + 1).to_s
      target.project = nil
      target.group = nil
      target.mode = :tiled
      target.flags = Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE
      target.layout = TiledLayout.new(target, target.geometry)
    else
      @desktops.delete_at(index)
      @desktops.each_with_index { |desktop, id| desktop.id = id }
      @windows.each_value(&:publish_desktop)
      @desktop_window_desktop = nil if @desktop_window_desktop == target
    end

    current = active_monitor&.active_desktop || @primary_monitor&.active_desktop
    @current_desktop_id = current&.id || 0
    publish_desktop_state if publish
    {
      ok: true,
      desktop: removed_id,
      key: removed_key,
      fallback: fallback&.id,
      released: released,
    }
  end

  def set_number_of_desktops(count)
    count = count.to_i
    return false if count < @monitors.length || count > 256
    return true if count == @desktops.length

    if count > @desktops.length
      (count - @desktops.length).times do
        id = @desktops.length
        append_desktop(key: next_automatic_desktop_key,
                       name: (id + 1).to_s,
                       flags: Desktop::FLAG_SLOT_BACKED |
                              Desktop::FLAG_AVAILABLE,
                       publish: false)
      end
    else
      removed = @desktops[count..]
      return false unless removed.all? do |desktop|
        desktop.available_placeholder? &&
          !desktop.static? &&
          !desktop.pinned? &&
          !desktop.active? &&
          desktop.children.empty?
      end
      removed.each { forget_desktop(_1) }
      @desktops.slice!(count, @desktops.length - count)
    end
    publish_desktop_state
    true
  end

  def read_utf8_property(wid, atom)
    @dpy.get_property(wid, atom, dpy.atom(:UTF8_STRING),
                      length: 16_384)&.value.to_s
  end

  def write_desktop_reply(wid, reply)
    return if !wid || wid == root_id
    body = JSON.generate(reply.merge(generation: @desktop_generation))
    @dpy.change_property(:replace, wid, :_RWM_DESKTOP_REPLY,
                         dpy.atom(:UTF8_STRING), 8, body.bytes)
  rescue X11::Error => e
    $logger.debug { "error writing desktop reply to #{wid}: #{e.message}" }
  end
  

  def change_property(atom, type, data, mode: :replace, format: 32)
    root.change_property(mode, atom, type, format, Array(data).pack("V*").unpack("C*"))
  end

  def current_desktop_id = (@current_desktop_id ||= root.get_property(:_NET_CURRENT_DESKTOP, :cardinal)&.value.to_i)
  def current_desktop    = desktops[current_desktop_id] || desktops[0]
  def root_id            = (@root_id ||= @dpy.screens.first.root)
  def root               = (@root ||=Window.new(self, root_id))
  def layout_for(w)
    if w.floating?
      return @floating
    else
      desktop = w.desktop
      current_layout = desktop&.layout || @floating
      
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

  def rootgeom           = (@rootgeom ||= root.get_geometry)

  # --- Struts / work area (EWMH _NET_WM_STRUT_PARTIAL) ----------------------

  def geometry(x, y, w, h)
    X11::Form::Geometry.new.tap { |g| g.x = x; g.y = y; g.width = w; g.height = h }
  end

  def invalidate_struts = (@struts = nil)
  def struts            = (@struts ||= read_struts)

  # Reserved-edge specs from every top-level window advertising a strut. Each is
  # the 12-element _NET_WM_STRUT_PARTIAL (a 4-element _NET_WM_STRUT is widened to
  # span the whole screen).
  def read_struts
    sw, sh = rootgeom.width, rootgeom.height
    root.query_tree.children.filter_map do |wid|
      v = dpy.get_property(wid, :_NET_WM_STRUT_PARTIAL, :cardinal, length: 12)&.value
      unless v.is_a?(Array) && v.length == 12
        s = dpy.get_property(wid, :_NET_WM_STRUT, :cardinal, length: 4)&.value
        next unless s.is_a?(Array) && s.length == 4
        v = [s[0], s[1], s[2], s[3], 0, sh - 1, 0, sh - 1, 0, sw - 1, 0, sw - 1]
      end
      next if v[0, 4].all?(&:zero?)
      v
    end
  rescue X11::Error => e
    $logger.debug { "error reading struts: #{e.message}" }
    []
  end

  def ranges_overlap?(a1, a2, b1, b2) = (a1 <= b2 && b1 <= a2)

  # A monitor's usable rectangle: its geometry minus any struts whose reserved
  # edge borders it.
  def work_area(monitor)
    return rootgeom if !monitor
    sw, sh = rootgeom.width, rootgeom.height
    x1, y1 = monitor.xoffset, monitor.yoffset
    x2, y2 = monitor.xoffset + monitor.width, monitor.yoffset + monitor.height

    struts.each do |s|
      left, right, top, bottom = s[0], s[1], s[2], s[3]
      y1 = [y1, top].max         if top    > 0 && ranges_overlap?(s[8],  s[9],  x1, x2 - 1)
      y2 = [y2, sh - bottom].min if bottom > 0 && ranges_overlap?(s[10], s[11], x1, x2 - 1)
      x1 = [x1, left].max        if left   > 0 && ranges_overlap?(s[4],  s[5],  y1, y2 - 1)
      x2 = [x2, sw - right].min  if right  > 0 && ranges_overlap?(s[6],  s[7],  y1, y2 - 1)
    end
    geometry(x1, y1, x2 - x1, y2 - y1)
  end

  # _NET_WORKAREA is one rect per desktop; publish the primary monitor's usable
  # area for each (a best-effort hint; EWMH has no per-monitor work area).
  def publish_workarea
    wa = work_area(@primary_monitor)
    change_property(:_NET_WORKAREA, :cardinal, [wa.x, wa.y, wa.width, wa.height] * @desktops.length)
  end

  def window(wid)
    return root if (wid == root.wid)
    return @windows[wid] if @windows[wid]
    adopt(wid)
  end

  def with_window(wid)
    w = window(wid)
    yield(w) if w
  end
  
  # Interned atom ids for Window::FLOAT_TYPES. Atoms are constant per session,
  # so memoise once to avoid repeated round-trips on the classification path.
  def float_type_atoms = (@float_type_atoms ||= Window::FLOAT_TYPES.map { dpy.atom(_1) })

  def update_client_list
    change_property(:_NET_CLIENT_LIST, :window, @windows.keys)
    update_client_list_stacking
    publish_desktop_occupancy
  end

  # _NET_CLIENT_LIST_STACKING: managed windows in bottom-to-top stacking order.
  # query_tree already returns children bottom-to-top, so filter it to the
  # windows we manage.
  def update_client_list_stacking
    stacking = root.query_tree.children.select { |wid| @windows.key?(wid) }
    change_property(:_NET_CLIENT_LIST_STACKING, :window, stacking)
  rescue X11::Error => e
    $logger.debug { "error updating _NET_CLIENT_LIST_STACKING: #{e.message}" }
  end

  # If we don't already know about this window, we "adopt" it.
  def adopt(wid, desktop=nil)
    return if wid.nil?
    w = @windows[wid] # To avoid infinite recursion, this *must not* use #window
    return w if w
    w = Window.new(self, wid)

    # Docks (panels/bars) are managed but special: kept on every desktop (never
    # tiled, floated, or focused), stacked above, keeping their own geometry, and
    # reserving screen space via struts.
    if w.dock?
      attr = w.get_window_attributes rescue nil
      return w if attr&.override_redirect
      w.floating = true
      w.mapped = (attr && attr.map_state != 0)
      @windows[wid] = w
      w.select_input(X11::Form::PropertyChangeMask)
      update_client_list
      invalidate_struts
      return w
    end

    # Dialogs/utilities/splashes and desktop windows are managed like ordinary
    # windows but never tiled: floated, kept on their own desktop, stacked by
    # type. They fall through to the normal path so they gain a stable identity
    # in @windows (preserving per-window state), a desktop assignment, and
    # client-list membership. Truly transient surfaces (menus/tooltips/popups)
    # are override-redirect and are rejected just below, so they never tile.
    if w.floaty_type? || w.desktop?
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
    desktop = Array(desktop).first
    desktop = @desktop_index_remap.fetch(desktop, desktop) if
      desktop && @desktop_index_remap
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

      # Desktop windows (e.g. the desktop/icon surface) stay pinned to their own
      # desktop and fill its monitor; they are never tiled, floated, reassigned
      # to another desktop, or focused. They are shown/hidden with their desktop.
      if w.desktop?
        w.resize_to_geom(w.desktop&.geometry || rootgeom)
        w.map   # Window#stack lowers desktop windows below everything else
        next
      end

      # Docks keep their own geometry and reserve space; map, recompute the
      # work area, and re-tile so windows avoid the reserved strut.
      if w.dock?
        w.map   # Window#stack raises docks
        invalidate_struts
        publish_workarea
        update_layout
        next
      end

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
        
        # Now place the window using the layout with updated monitor information
        win_layout.place(w, @focus)
      end
      
      w.map
      set_focus(wid) unless w.special?
    end
    # Mapping (re)stacks the window, so refresh the stacking hint. (adopt
    # publishes the list before the window is mapped.)
    update_client_list_stacking
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

    # Keep inactive layouts populated too. This matters when adopting mapped
    # clients after a WM restart: they already exist, so no later MapRequest
    # will place them before their desktop is shown.
    if !w.floating? && d.layout && !d.layout.find(w)
      d.layout.place(w, @focus)
    end

    if d.active?
      w.show
    else
      w.hide
    end
    
    d.update_layout if d.active?
    old.update_layout if old&.active?
    publish_desktop_occupancy
  end

  def change_desktop(d) = change_desktop_on_monitor(active_monitor, d)
    
  def change_desktop_on_monitor(curr_monitor, d)
    target = d.is_a?(Desktop) ? d : desktops[d]
    return if !target

    current = curr_monitor.active_desktop

    # Already showing the target on this monitor: just refresh.
    if current == target
      remember_desktop(curr_monitor, target)
      update_layout
      publish_desktop_history
      publish_desktop_generation
      return target.show
    end

    # If the target is currently shown on another monitor, that monitor takes
    # over this monitor's desktop (the two simply swap).
    other = @monitors.find { |m| m != curr_monitor && m.active_desktop == target }

    current&.hide
    # If the target was visible on another monitor, hide it first so that
    # showing it on this monitor re-runs each window's monitor relocation
    # (floating windows reposition on show, not via the layout).
    target.hide if other
    curr_monitor.active_desktop = target
    remember_desktop(curr_monitor, target)

    if other
      other.active_desktop = current
      if current
        remember_desktop(other, current)
        point_layout_at(current, other)
        current.show
        set_current_desktop(current.id, other)
      end
    end

    point_layout_at(target, curr_monitor)
    target.show
    set_current_desktop(target.id, curr_monitor)
    update_layout

    f = target.mapped_regular_children&.first
    set_focus(f.wid) if f
  end

  # Point a tiled desktop's layout at a monitor's geometry. Floating desktops
  # have no layout — their windows position themselves in place()/show().
  def point_layout_at(desktop, monitor)
    desktop.layout&.update_geometry(monitor.geometry)
  end


  def set_focus(wid)
    return if wid == root_id
    with_window(wid) do |w|
      w = window(wid)

      # Docks never take the keyboard.
      return if w.dock?

      # Desktop/backdrop windows may receive the keyboard (so their own
      # shortcuts work while the pointer is over them), but they are not the
      # WM's logical focus target for tiling/commands and get no focus border.
      # Global keybindings keep working: sxhkd's root grabs still fire whatever
      # holds the input focus.
      if w.desktop?
        w.set_input_focus(:parent)
        return
      end

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
      invalidate_struts   # a dock may have gone; recompute reserved space
      publish_workarea
      update_layout
      update_client_list
    end
  end
  
  # # X Event-handlers

  def on_error(ev) = destroy_window(ev.bad_resource_id)

  def on_map_notify(ev)      = (window(ev.window)&.mapped = true)
  def on_unmap_notify(ev)
    w = window(ev.window)
    return unless w
    w.mapped = false
    if w.dock?
      invalidate_struts
      publish_workarea
      update_layout
    end
  end
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
    $logger.debug { "Property Notify: #{name}" }
    if name == "_NET_WM_STRUT_PARTIAL" || name == "_NET_WM_STRUT"
      invalidate_struts
      publish_workarea
      update_layout
    end
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

  def on_net_number_of_desktops(_, count) = set_number_of_desktops(count)
  def on_net_current_desktop(_, d) = change_desktop(d)

  # EWMH _NET_WM_STATE: a message carries an action (remove/add/toggle) and up
  # to two state atoms. Honour the action and distinguish fullscreen (whole
  # monitor) from maximize (work area); a full maximize arrives as VERT+HORZ.
  def on_net_wm_state(wid, action, prop1, prop2, source)
    with_window(wid) do |w|
      [prop1, prop2].each do |prop|
        case prop
        when 0 then next
        when dpy.atom(:_NET_WM_STATE_FULLSCREEN)
          w.set_wm_state_flag(action, :fullscreen)
        when dpy.atom(:_NET_WM_STATE_MAXIMIZED_VERT),
             dpy.atom(:_NET_WM_STATE_MAXIMIZED_HORZ)
          w.set_wm_state_flag(action, :maximized)
        end
      end
    end
  end

  def on_net_wm_desktop(wid, d) = move_to_desktop(wid, d)

  # EWMH: ask the WM to close a specific window gracefully.
  def on_net_close_window(wid, *) = window(wid)&.request_close

  # Close the focused window (kept for the keybinding that sends this to root).
  def on_wm_delete_window(*) = @focus&.request_close

  # # RWM specific ClientMessages

  # Ensure a desktop from a JSON _RWM_DESKTOP_SPEC property on the requester
  # window. The result is written back as JSON in _RWM_DESKTOP_REPLY.
  def on_rwm_ensure_desktop(requestor, version, _unused1, _unused2,
                            _unused3, _unused4)
    if version != DESKTOP_PROTOCOL_VERSION
      return write_desktop_reply(
        requestor,
        ok: false,
        error: "unsupported desktop protocol version #{version}",
      )
    end

    spec = JSON.parse(read_utf8_property(requestor, :_RWM_DESKTOP_SPEC))
    monitor = if spec["view"]
      candidate = if spec["monitor"].nil?
        active_monitor
      else
        @monitors[Integer(spec["monitor"])]
      end
      raise ArgumentError, "monitor does not exist" unless candidate
      candidate
    end

    reply = ensure_desktop(spec)
    if monitor
      change_desktop_on_monitor(monitor, reply[:desktop])
    end
    write_desktop_reply(requestor, reply)
  rescue JSON::ParserError, ArgumentError, TypeError => e
    write_desktop_reply(requestor, ok: false, error: e.message)
  end

  def on_rwm_view_desktop(_, desktop, monitor_id, _unused1, _unused2,
                          _unused3)
    monitor = monitor_id == UINT32_MAX ? active_monitor : @monitors[monitor_id]
    change_desktop_on_monitor(monitor, desktop) if monitor
  end

  # Numeric keybindings address Rebar's high-level contexts, not the flat EWMH
  # backing desktop at the same number. data[1] is monitor+1; zero means active.
  def on_rwm_view_group(_, address, monitor_token, _unused1, _unused2,
                        _unused3)
    monitor = monitor_token.zero? ? active_monitor :
                                    @monitors[monitor_token - 1]
    return unless monitor
    desktop = desktop_for_group_address(address, monitor)
    change_desktop_on_monitor(monitor, desktop)
  rescue ArgumentError => e
    $logger.debug { "ignoring _RWM_VIEW_GROUP #{address}: #{e.message}" }
  end

  def on_rwm_send_to_group(wid, address, monitor_token, _unused1, _unused2,
                           _unused3)
    monitor = monitor_token.zero? ? active_monitor :
                                    @monitors[monitor_token - 1]
    return unless monitor
    target = desktop_for_group_address(address, monitor)
    client = @windows[wid] || @focus
    move_to_desktop(client.wid, target) if client
  rescue ArgumentError => e
    $logger.debug { "ignoring _RWM_SEND_TO_GROUP #{address}: #{e.message}" }
  end

  # Add a temporary empty tiled view to the group shown on a monitor. Rebar
  # sends monitor+1; zero retains the active-monitor convention.
  def on_rwm_add_group_view(_, monitor_token, _unused1, _unused2, _unused3,
                            _unused4)
    monitor = monitor_token.zero? ? active_monitor :
                                    @monitors[monitor_token - 1]
    add_group_view(monitor)
  rescue ArgumentError => e
    $logger.debug { "ignoring _RWM_ADD_GROUP_VIEW: #{e.message}" }
  end

  def on_rwm_remove_desktop(requestor, desktop, flags, fallback,
                            _unused1, _unused2)
    fallback = nil if fallback == UINT32_MAX
    reply = remove_desktop(desktop,
                           force: flags & REMOVE_FORCE != 0,
                           fallback_index: fallback)
    write_desktop_reply(requestor, reply)
  end

  def on_rwm_move_desktop(requestor, version, desktop, target,
                          _unused1, _unused2)
    if version != DESKTOP_PROTOCOL_VERSION
      return write_desktop_reply(
        requestor,
        ok: false,
        error: "unsupported desktop protocol version #{version}",
      )
    end
    target = nil if target == UINT32_MAX
    reply = move_desktop(desktop, target_index: target)
    write_desktop_reply(requestor, reply)
  end

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
    if node = @focus.desktop&.layout&.find(@focus)
      node = node.parent if node.is_a?(Leaf)
      node.dir = node.dir == :lr ? :tb : :lr
      @focus.desktop&.update_layout
    end
  end

  # Swap nodes in the nearest parent node of the focused window
  def on_rwm_swap_nodes(_)
    # FIXME: Respect the window passed instead of doing it to @focus
    # no matter what
    return if !@focus || @focus.special?
    # FIXME: Move to layout?
    if node = @focus.desktop&.layout&.find(@focus)
      node = node.parent if node.is_a?(Leaf)
      tmp = node.nodes[0]
      node.nodes[0] = node.nodes[1]
      node.nodes[1] = tmp
      update_layout
    end
  end

  # Pixels a floating window moves per _RWM_MOVE step.
  FLOAT_MOVE_STEP = 20

  # Move the focused window, either swapping it into the container
  # of the nearest leaf (if tiled), or moving it stepwise if floating.
  # Direction stays a (cached) atom name on purpose — it's hand-written in
  # keybindings, where `Left` reads better than an integer offset.
  def on_rwm_move(_,dir)
    return if !@focus || @focus.special?
    dir = dpy.get_atom_name(dir).downcase.to_sym

    if @focus.floating?
      g = @focus.get_geometry

      case dir
      when :left  then @focus.configure(x: g.x - FLOAT_MOVE_STEP)
      when :right then @focus.configure(x: g.x + FLOAT_MOVE_STEP)
      when :down  then @focus.configure(y: g.y + FLOAT_MOVE_STEP)
      when :up    then @focus.configure(y: g.y - FLOAT_MOVE_STEP)
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
