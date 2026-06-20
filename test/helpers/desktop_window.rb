# Test helper: create a _NET_WM_WINDOW_TYPE_DESKTOP window pinned to a given
# desktop (default 0) and keep it alive, for exercising desktop-window
# confinement. Usage: ruby test/helpers/desktop_window.rb [desktop_index]
require "bundler/setup"
require "X11"

dpy   = X11::Display.new
root  = dpy.screens.first.root
depth = dpy.get_geometry(root).depth
desktop = (ARGV[0] || "0").to_i

wid = dpy.create_window(0, 0, 300, 200, depth: depth)
dpy.change_property(:replace, wid, :_NET_WM_WINDOW_TYPE, :atom, 32,
                    [dpy.atom(:_NET_WM_WINDOW_TYPE_DESKTOP)].pack("V*").unpack("C*"))
dpy.change_property(:replace, wid, :_NET_WM_DESKTOP, :cardinal, 32,
                    [desktop].pack("V*").unpack("C*"))
dpy.map_window(wid)
dpy.flush

sleep 3600
