# Test helper: create a _NET_WM_WINDOW_TYPE_DIALOG window on a given desktop
# (default 0) and keep it alive, for exercising that dialogs are managed (kept
# in @windows / _NET_CLIENT_LIST) and floated rather than tiled.
# Usage: ruby test/helpers/dialog_window.rb [desktop_index]
require "bundler/setup"
require "X11"

dpy     = X11::Display.new
root    = dpy.screens.first.root
depth   = dpy.get_geometry(root).depth
desktop = (ARGV[0] || "0").to_i

wid = dpy.create_window(40, 40, 320, 240, depth: depth)
dpy.change_property(:replace, wid, :_NET_WM_WINDOW_TYPE, :atom, 32,
                    [dpy.atom(:_NET_WM_WINDOW_TYPE_DIALOG)].pack("V*").unpack("C*"))
dpy.change_property(:replace, wid, :_NET_WM_DESKTOP, :cardinal, 32,
                    [desktop].pack("V*").unpack("C*"))
dpy.map_window(wid)
dpy.flush

sleep 3600
