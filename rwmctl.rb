#!/usr/bin/env ruby

require "rbconfig"

# rwmctl is commonly invoked while standing in the project it is about to
# describe. Bundler normally discovers Gemfile from the current directory, so
# a plain `require "bundler/setup"` would accidentally activate that project's
# bundle and make RubyWM's X11 dependency unavailable.
#
# Merely setting BUNDLE_GEMFILE here handles an ordinary shell. If rwmctl was
# launched from another project's `bundle exec`, however, Bundler was loaded
# through RUBYOPT before this file started. Re-exec once with those injected
# variables removed, then activate rwmctl's own bundle deterministically.
RWMCTL_GEMFILE = File.expand_path("Gemfile", __dir__)
RWMCTL_BOOTSTRAP = "RWMCTL_OWN_BUNDLE"
if defined?(Bundler) && ENV[RWMCTL_BOOTSTRAP] != "1"
  clean = ENV.to_h.reject do |name, _value|
    name.start_with?("BUNDLE_", "BUNDLER_") ||
      %w[RUBYOPT RUBYLIB].include?(name)
  end
  clean["BUNDLE_GEMFILE"] = RWMCTL_GEMFILE
  clean[RWMCTL_BOOTSTRAP] = "1"
  exec(
    clean,
    RbConfig.ruby,
    File.realpath(__FILE__),
    *ARGV,
    unsetenv_others: true,
  )
end

ENV["BUNDLE_GEMFILE"] = RWMCTL_GEMFILE
require 'bundler/setup'
require 'X11'
require 'json'
require 'stringio'
require_relative "desktop_navigation"

class Rwmctl
  UINT32_MAX = 0xffffffff
  PROTOCOL_VERSION = 1
  REMOVE_FORCE = 1 << 0

  def initialize(argv, out: $stdout, err: $stderr)
    @argv = argv.dup
    @out = out
    @err = err
  end

  def run
    command = @argv.shift
    unless %w[list current ensure edit view group send move remove count].include?(command)
      usage
      return 1
    end
    @dpy = X11::Display.new
    @root = @dpy.default_root
    case command
    when "list"    then list
    when "current" then current
    when "ensure"  then ensure_desktop
    when "edit"    then ensure_desktop(update_only: true)
    when "view"    then view
    when "group"   then group
    when "send"    then send_to_group
    when "move"    then move
    when "remove"  then remove
    when "count"   then set_count
    end
    0
  rescue ArgumentError, TypeError, JSON::ParserError, X11::Error,
         SystemCallError => e
    @err.puts("rwmctl: #{e.message}")
    1
  end

  private

  def usage
    @err.puts <<~USAGE
      usage:
        rwmctl.rb list [--json]
        rwmctl.rb current [--monitor INDEX] [--field FIELD | --json]
        rwmctl.rb ensure KEY [--name NAME] [--pwd DIR] [--group NAME]
                         [--mode tiled|floating] [--pinned] [--view]
                         [--monitor INDEX]
        rwmctl.rb edit KEY|current [--key NEW_KEY] [--name NAME]
                       [--pwd DIR|--clear-pwd] [--group NAME|--clear-group]
                       [--rekey-group NEW_GROUP] [--mode tiled|floating]
                       [--pinned] [--view] [--monitor INDEX]
        rwmctl.rb view KEY|INDEX [--monitor INDEX]
        rwmctl.rb view next|previous [--monitor INDEX]
        rwmctl.rb group next|previous|KEY|DESKTOP_NUMBER [--monitor INDEX]
        rwmctl.rb send KEY|DESKTOP_NUMBER [--monitor INDEX]
        rwmctl.rb move KEY|GROUP|INDEX [--first | --to DESKTOP_NUMBER]
        rwmctl.rb remove KEY|INDEX [--force] [--fallback KEY|INDEX]
        rwmctl.rb count NUMBER

      Existing raw desktop/monitor index references are zero-based. Numeric
      group references and --to use the one-based address displayed by Rebar.
      --project remains an alias for --pwd.
    USAGE
  end

  def property(atom, type, length: 16_384)
    @dpy.get_property(@root, atom, type, length: length)&.value
  end

  def cardinals(atom)
    value = property(atom, :cardinal)
    value.nil? ? [] : Array(value)
  end

  def utf8_list(atom)
    value = property(atom, @dpy.atom(:UTF8_STRING))
    return [] if value.nil?
    values = value.to_s.split("\0", -1)
    values.pop if values.last == ""
    values
  end

  def desktop_rows
    count = cardinals(:_NET_NUMBER_OF_DESKTOPS).first.to_i
    names = utf8_list(:_NET_DESKTOP_NAMES)
    keys = utf8_list(:_RWM_DESKTOP_KEYS)
    projects = utf8_list(:_RWM_DESKTOP_PROJECTS)
    groups = utf8_list(:_RWM_DESKTOP_GROUPS)
    modes = cardinals(:_RWM_DESKTOP_MODES)
    flags = cardinals(:_RWM_DESKTOP_FLAGS)
    client_counts = cardinals(:_RWM_DESKTOP_CLIENT_COUNTS)
    if client_counts.length != count
      client_counts = standard_desktop_client_counts(count)
    end
    visible = cardinals(:_RWM_VISIBLE_DESKTOPS)

    count.times.map do |index|
      {
        index: index,
        key: keys[index] || "desktop-#{index + 1}",
        name: names[index] || (index + 1).to_s,
        project: blank_to_nil(projects[index]),
        group: blank_to_nil(groups[index]),
        mode: modes[index] == 1 ? "floating" : "tiled",
        flags: flags[index].to_i,
        occupied: client_counts[index].to_i.positive?,
        monitors: visible.each_index.select { visible[_1] == index },
      }
    end
  end

  def blank_to_nil(value)
    value.nil? || value.empty? ? nil : value
  end

  def standard_desktop_client_counts(count)
    counts = Array.new(count, 0)
    clients = property(:_NET_CLIENT_LIST, :window)
    Array(clients).each do |wid|
      value = @dpy.get_property(
        wid, :_NET_WM_DESKTOP, :cardinal, length: 1
      )&.value
      index = Array(value).first
      next unless index && index != UINT32_MAX && index < count
      counts[index] += 1
    rescue X11::Error
      next
    end
    counts
  end

  def history_for_monitor(monitor, rows, current)
    count = rows.length
    return [] if count.zero?
    visible = cardinals(:_RWM_VISIBLE_DESKTOPS)
    monitor = visible.index(current) || 0 if monitor == UINT32_MAX
    cardinals(:_RWM_DESKTOP_HISTORY)
      .slice(monitor * count, count)
      .to_a
      .reject { _1 == UINT32_MAX || _1 >= count }
  end

  def list
    json = @argv.delete("--json")
    raise ArgumentError, "unexpected arguments: #{@argv.join(" ")}" unless @argv.empty?
    rows = desktop_rows
    if json
      @out.puts(JSON.pretty_generate(rows))
      return
    end

    rows.each do |row|
      visible = row[:monitors].empty? ? "" : " [monitor #{row[:monitors].join(",")}]"
      details = [row[:mode], row[:group], row[:project]].compact.join(" · ")
      @out.puts format("%3d  %-24s %-20s %s%s",
                       row[:index], row[:key], row[:name], details, visible)
    end
  end

  def pointer_monitor_index
    screens = @dpy.xinerama_query_screens.screens
    return 0 if screens.empty?

    pointer = @dpy.query_pointer(@root)
    screens.index do |screen|
      pointer.root_x >= screen.x_org &&
        pointer.root_x < screen.x_org + screen.width &&
        pointer.root_y >= screen.y_org &&
        pointer.root_y < screen.y_org + screen.height
    end || 0
  rescue X11::Error
    0
  end

  def current
    monitor = nil
    field = nil
    json = false
    until @argv.empty?
      option = @argv.shift
      case option
      when "--monitor" then monitor = Integer(take_value(option))
      when "--field"   then field = take_value(option)
      when "--json"    then json = true
      else raise ArgumentError, "unknown current option: #{option}"
      end
    end
    raise ArgumentError, "--field and --json cannot be combined" if field && json

    row = active_desktop_row(monitor)
    output = row.merge(number: row[:index] + 1, pwd: row[:project])
    if field
      field = "pwd" if field == "project"
      allowed = %w[index number key name pwd group mode occupied]
      raise ArgumentError, "unknown current field: #{field}" unless
        allowed.include?(field)
      @out.puts(output[field.to_sym])
    elsif json
      @out.puts(JSON.generate(output))
    else
      details = [output[:group], output[:pwd]].compact.join(" · ")
      @out.puts format("%d  %s  %s%s",
                       output[:number],
                       output[:key],
                       output[:name],
                       details.empty? ? "" : "  #{details}")
    end
  end

  def active_desktop_row(monitor = nil)
    monitor ||= pointer_monitor_index
    visible = cardinals(:_RWM_VISIBLE_DESKTOPS)
    raise ArgumentError, "monitor does not exist" if
      !visible.empty? && visible[monitor].nil?
    index = visible[monitor]
    index ||= cardinals(:_NET_CURRENT_DESKTOP).first
    row = desktop_rows[index] if index
    raise ArgumentError, "current desktop does not exist" unless row
    row
  end

  def take_value(option)
    value = @argv.shift
    raise ArgumentError, "#{option} needs a value" if value.nil?
    value
  end

  def ensure_desktop(update_only: false)
    reference = @argv.shift
    verb = update_only ? "edit" : "ensure"
    raise ArgumentError, "#{verb} needs a desktop key" if reference.nil?
    spec = {}

    until @argv.empty?
      option = @argv.shift
      case option
      when "--key"
        raise ArgumentError, "--key is only valid with edit" unless update_only
        spec["new_key"] = take_value(option)
      when "--name"    then spec["name"] = take_value(option)
      when "--pwd", "--project"
        spec["project"] = File.expand_path(take_value(option))
      when "--clear-pwd"
        spec["project"] = nil
      when "--group"
        raise ArgumentError, "--group and --rekey-group cannot be combined" if
          spec.key?("rename_group")
        spec["group"] = take_value(option)
      when "--clear-group"
        raise ArgumentError, "--clear-group and --rekey-group cannot be combined" if
          spec.key?("rename_group")
        spec["group"] = nil
      when "--rekey-group"
        raise ArgumentError, "--group and --rekey-group cannot be combined" if
          spec.key?("group")
        spec["rename_group"] = take_value(option)
      when "--mode"    then spec["mode"] = take_value(option)
      when "--pinned"  then spec["pinned"] = true
      when "--view"    then spec["view"] = true
      when "--monitor" then spec["monitor"] = Integer(take_value(option))
      else raise ArgumentError, "unknown #{verb} option: #{option}"
      end
    end

    row = active_desktop_row(spec["monitor"]) if
      update_only && reference == "current"
    key = row ? row[:key] : reference
    if update_only && desktop_rows.none? { _1[:key] == key }
      raise ArgumentError, "desktop key does not exist: #{key}"
    end
    spec["key"] = key
    spec["update_only"] = true if update_only

    with_request_window do |requestor|
      write_utf8(requestor, :_RWM_DESKTOP_SPEC, JSON.generate(spec))
      send_message(:_RWM_ENSURE_DESKTOP, [PROTOCOL_VERSION],
                   window: requestor)
      reply = wait_for_reply(requestor)
      raise ArgumentError, reply["error"] unless reply["ok"]
      @out.puts(JSON.generate(reply))
    end
  end

  def resolve_desktop(reference)
    raise ArgumentError, "desktop reference is required" if reference.nil?
    if reference.match?(/\A\d+\z/)
      index = Integer(reference)
      raise ArgumentError, "desktop index does not exist" unless desktop_rows[index]
      return index
    end

    rows = desktop_rows
    row = rows.find { _1[:key] == reference }
    unless row
      group_rows = rows.select {
        _1[:group].to_s.casecmp?(reference)
      }
      row = group_rows.find {
        _1[:flags].to_i & DesktopNavigation::FLAG_GROUP_ROOT != 0
      } || group_rows.first
    end
    raise ArgumentError, "unknown desktop key or group: #{reference}" unless row
    row[:index]
  end

  def view
    reference = @argv.shift
    monitor = UINT32_MAX
    until @argv.empty?
      option = @argv.shift
      case option
      when "--monitor" then monitor = Integer(take_value(option))
      else raise ArgumentError, "unknown view option: #{option}"
      end
    end
    desktop = if %w[next previous].include?(reference)
      DesktopNavigation.new(
        desktop_rows,
        current: current_desktop_for(monitor),
      ).view_target(reference)
    else
      resolve_desktop(reference)
    end
    send_message(:_RWM_VIEW_DESKTOP, [desktop, monitor])
    @dpy.flush
  end

  def group
    reference = @argv.shift
    reference = @argv.shift if reference == "view"
    monitor = UINT32_MAX
    until @argv.empty?
      option = @argv.shift
      case option
      when "--monitor" then monitor = Integer(take_value(option))
      else raise ArgumentError, "unknown group option: #{option}"
      end
    end
    desktop = group_target_for(reference, monitor)
    send_message(:_RWM_VIEW_DESKTOP, [desktop, monitor])
    @dpy.flush
  end

  def group_target_for(reference, monitor)
    rows = desktop_rows
    current = current_desktop_for(monitor)
    DesktopNavigation.new(
      rows,
      current: current,
      history: history_for_monitor(monitor, rows, current),
    ).group_target(reference)
  end

  def send_to_group
    reference = @argv.shift
    monitor = UINT32_MAX
    until @argv.empty?
      option = @argv.shift
      case option
      when "--monitor" then monitor = Integer(take_value(option))
      else raise ArgumentError, "unknown send option: #{option}"
      end
    end
    desktop = group_target_for(reference, monitor)
    focused = Array(property(:_NET_ACTIVE_WINDOW, :window)).first
    raise ArgumentError, "there is no active window" if
      focused.nil? || focused.zero?
    send_message(:_NET_WM_DESKTOP, [desktop], window: focused)
    @dpy.flush
  end

  def current_desktop_for(monitor)
    if monitor != UINT32_MAX
      current = cardinals(:_RWM_VISIBLE_DESKTOPS)[monitor]
      raise ArgumentError, "monitor does not exist" if current.nil?
      return current
    end
    cardinals(:_NET_CURRENT_DESKTOP).first.to_i
  end

  def move
    desktop = resolve_desktop(@argv.shift)
    target = UINT32_MAX
    target_set = false
    until @argv.empty?
      option = @argv.shift
      case option
      when "--first"
        raise ArgumentError, "move target specified more than once" if target_set
        target_set = true
      when "--to"
        raise ArgumentError, "move target specified more than once" if target_set
        number = Integer(take_value(option))
        raise ArgumentError, "desktop number must be at least 1" if number < 1
        target = number - 1
        target_set = true
      else raise ArgumentError, "unknown move option: #{option}"
      end
    end

    with_request_window do |requestor|
      send_message(
        :_RWM_MOVE_DESKTOP,
        [PROTOCOL_VERSION, desktop, target],
        window: requestor,
      )
      reply = wait_for_reply(requestor)
      raise ArgumentError, reply["error"] unless reply["ok"]
      @out.puts(JSON.generate(reply))
    end
  end

  def remove
    desktop = resolve_desktop(@argv.shift)
    flags = 0
    fallback = UINT32_MAX
    until @argv.empty?
      option = @argv.shift
      case option
      when "--force" then flags |= REMOVE_FORCE
      when "--fallback" then fallback = resolve_desktop(take_value(option))
      else raise ArgumentError, "unknown remove option: #{option}"
      end
    end

    with_request_window do |requestor|
      send_message(:_RWM_REMOVE_DESKTOP,
                   [desktop, flags, fallback],
                   window: requestor)
      reply = wait_for_reply(requestor)
      raise ArgumentError, reply["error"] unless reply["ok"]
      @out.puts(JSON.generate(reply))
    end
  end

  def set_count
    count = Integer(@argv.shift)
    raise ArgumentError, "unexpected arguments: #{@argv.join(" ")}" unless @argv.empty?
    send_message(:_NET_NUMBER_OF_DESKTOPS, [count])
    @dpy.flush
  end

  def write_utf8(window, atom, body)
    @dpy.change_property(:replace, window, atom,
                         @dpy.atom(:UTF8_STRING), 8, body.bytes)
  end

  def with_request_window
    depth = @dpy.display_info.screens.first.root_depth
    requestor = @dpy.create_window(
      -1, -1, 1, 1,
      depth: depth,
      values: { X11::Form::CWOverrideRedirect => 1 },
    )
    yield(requestor)
  ensure
    @dpy.destroy_window(requestor) if requestor
    @dpy.flush
  end

  # pure-x11 currently pretty-prints every ClientMessage for debugging. Keep
  # this semantic command's stdout machine-readable until that library detail
  # is removed.
  def send_message(type, data, window: @root)
    previous_stdout = $stdout
    $stdout = StringIO.new
    @dpy.client_message(
      window: window,
      destination: @root,
      mask: X11::Form::SubstructureNotifyMask |
            X11::Form::SubstructureRedirectMask,
      type: type,
      data: data,
    )
  ensure
    $stdout = previous_stdout
  end

  def wait_for_reply(requestor)
    200.times do
      value = @dpy.get_property(
        requestor,
        :_RWM_DESKTOP_REPLY,
        @dpy.atom(:UTF8_STRING),
        length: 16_384,
      )&.value
      return JSON.parse(value.to_s) if value
      sleep 0.01
    end
    raise ArgumentError, "window manager did not reply"
  end
end

exit(Rwmctl.new(ARGV).run) if $PROGRAM_NAME == __FILE__
