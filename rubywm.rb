
# (C) 2024 Vidar Hokstad <vidar@hokstad.com>
# Licensed under the MIT license.
#
# Based on TinyWM by Nick Welch
# Lots of inspiration from Katriawm
# https://www.uninformativ.de/git/katriawm/files.html
#

require 'bundler/setup'
require 'X11'
require 'set'

require_relative 'window.rb'
require_relative 'wm.rb'
require_relative 'desktop.rb'
require_relative 'tiled.rb'
require_relative 'type_dispatcher'
require_relative 'geom.rb'
require_relative 'leaf.rb'
require_relative 'node.rb'

Thread.abort_on_exception = true

dpy = X11::Display.new
$wm = WindowManager.new(dpy, num_desktops: 10)

# FIXME: This can also go into the WindowManager class

d = Dispatcher.new($wm)
d.on(:client_message) do |ev|
  data = ev.data.unpack("V*")
  name = dpy.get_atom_name(ev.type)
  d.(name, ev.window, *data)
end

loop do
  ev = nil
  begin
    ev = dpy.next_packet
  rescue Interrupt
    raise
  rescue Exception => e
    pp e
  end

  p ev
  d.(ev.class, ev)
end
