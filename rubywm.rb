
# Based on TinyWM by Nick Welch
# Lots of inspiration from Katriawm
# https://www.uninformativ.de/git/katriawm/files.html
#

require 'X11'
require 'set'

require_relative 'window.rb'
require_relative 'wm.rb'
require_relative 'desktop.rb'
require_relative 'tiled.rb'
require_relative '../type_dispatcher'

dpy = X11::Display.new

$wm = WindowManager.new(dpy, num_desktops: 10)

start = nil
attr = nil

d = TypeDispatcher.new($wm)
d.on(:client_message) do |ev|
  data = ev.data.unpack("V*")
  name = dpy.get_atom_name(ev.type)
  p [name, data]
  d.(name, ev.window, *data)
end

loop do
  # FIXME: Select properly
  ev = nil
  begin
    ev = dpy.next_packet
  rescue Interrupt
    raise
  rescue Exception => e
    pp e
  end

  p ev
  
  case ev
  when X11::Form::ButtonPress
    if ev.child # Whichever button, we want to know more about this window
      w = $wm.window(ev.child)
      attr = w.get_geometry rescue nil
      if attr
        $wm.set_focus(w.wid)
        start = ev
      end
    end
  when X11::Form::MotionNotify # if start.button == 1 we move; if 3 we resize, all with the same request:
    # TODO: If floating, do this; if tiling, find neighours and resize them too.

    if ev.child != start.child
      $wm.set_focus(ev.child)
    end
    
    p [:MOTION, start, attr]
    if start
      xdiff = ev.root_x - start.root_x;
      ydiff = ev.root_y - start.root_y;

      if start&.child && attr
        w = $wm.window(start.child)

        # FIXME: Any other types we don't want to allow moving or resizing
        begin
          next if w.special?
        rescue # FIXME
        end
        p w
        if start.detail == 1 # Move
          w.configure(x: attr.x + xdiff, y: attr.y + ydiff)
        elsif start.detail == 3 # Resize
          # If left/above the centre point, we grow/shrink the window to the left/top
          # otherwise to the right/bottom. Doing it to the left/top requires
          # moving it at the same time.
          attr.x = attr.x + (ev.event_x-attr.x < attr.width / 2 ? xdiff : 0)
          attr.y = attr.y + (ev.event_y-attr.y < attr.height/ 2 ? ydiff : 0)
          attr.width  = attr.width + (ev.event_x-attr.x < attr.width  / 2 ? -xdiff : xdiff)
          attr.height = attr.height+ (ev.event_y-attr.y < attr.height / 2 ? -ydiff : ydiff)
          start.root_x = ev.root_x
          start.root_y = ev.root_y
          w.configure(x: attr.x, y: attr.y, width: attr.width, height: attr.height)
        end
      end
    end
  when X11::Form::ButtonRelease
    # Make sure we don't accidentally operate on another window.
    start.child = nil if start
  else
    d.(ev.class, ev)
  end
end
