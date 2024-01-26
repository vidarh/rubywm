
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
require 'yaml'

require_relative 'window.rb'
require_relative 'wm.rb'
require_relative 'desktop.rb'
require_relative 'tiled.rb'
require_relative 'type_dispatcher'
require_relative 'geom.rb'
require_relative 'leaf.rb'
require_relative 'node.rb'

Thread.abort_on_exception = true

if ARGV.shift == "--debug"
  Thread.new do
    binding.irb
  end
end

# FIXME: This is only the first step towards splitting out config.
# E.g. honor a config flag and/or XDG, but for now I'm just migrating
# the config out of the WindowManager class.
config = YAML.load_file(__dir__ + "/config.yml", symbolize_names: true)

dpy = X11::Display.new
$wm = WindowManager.new(dpy, config)

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
  begin
    d.(ev.class, ev)
  rescue X11::Error => e
    pp e
  end
end
