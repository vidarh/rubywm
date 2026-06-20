# Test helper: create a _NET_WM_WINDOW_TYPE_DOCK window as a bottom bar on
# monitor 0, advertising a matching _NET_WM_STRUT_PARTIAL, and keep it alive.
# Usage: ruby test/helpers/dock_window.rb [bar_height]
require "bundler/setup"
require "X11"

dpy   = X11::Display.new
root  = dpy.screens.first.root
g     = dpy.get_geometry(root)
sw, sh, depth = g.width, g.height, g.depth
bar   = (ARGV[0] || "40").to_i

x, y, w, h = 0, sh - bar, sw, bar
wid = dpy.create_window(x, y, w, h, depth: depth)
dpy.change_property(:replace, wid, :_NET_WM_WINDOW_TYPE, :atom, 32,
                    [dpy.atom(:_NET_WM_WINDOW_TYPE_DOCK)].pack("V*").unpack("C*"))
# _NET_WM_STRUT_PARTIAL: reserve `bar` px at the bottom across the full width.
strut = [0, 0, 0, bar,  0, 0, 0, 0,  0, 0, 0, sw - 1]
dpy.change_property(:replace, wid, :_NET_WM_STRUT_PARTIAL, :cardinal, 32,
                    strut.pack("V*").unpack("C*"))
dpy.map_window(wid)
dpy.flush

sleep 3600
