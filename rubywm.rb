
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
require 'logger'

require_relative 'options'
require_relative 'window.rb'
require_relative 'wm.rb'
require_relative 'desktop.rb'
require_relative 'tiled.rb'
require_relative 'type_dispatcher'
require_relative 'geom.rb'
require_relative 'leaf.rb'
require_relative 'node.rb'

def severity_colorize(severity) = case severity
  when "DEBUG" then "\e[34m"  # blue
  when "INFO"  then "\e[32m"  # green
  when "WARN"  then "\e[33m"  # yellow
  when "ERROR" then "\e[31m"  # red
  else ""
end

$logger = Logger.new(STDERR)
$logger.level = Logger::INFO
$logger.formatter = proc do |severity, datetime, progname, msg|
  "#{severity_colorize(severity)}#{severity}\e[0m \e[36m#{datetime.strftime("%m/%d %H:%M:%S")}\e[0m \e[1m#{msg}\e[0m\n"
end

Thread.abort_on_exception = true

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
  $logger.info("Client Message: #{name}(#{data.map(&:to_s).join(", ")})")
  d.(name, ev.window, *data)
end

opts = Options.parse(ARGV)

if opts[:drb]
  $logger.info("Starting DRb service")
  require_relative './drb'
  start_drb_service
end

if opts[:debug]
  Thread.new do
    binding.irb
  end
end


loop do
  ev = nil
  begin
    ev = dpy.next_packet
  rescue Interrupt
    raise
  rescue Exception => e
    $logger.error(e.inspect)
    next
  end

  # next_packet returns nil when the X connection's read queue is closed, i.e.
  # the server went away. Exit cleanly instead of spinning on dispatch(nil)
  # (which previously busy-looped at 100% CPU and left orphaned processes).
  if ev.nil?
    $logger.info("X connection closed; exiting")
    break
  end

  $logger.debug("Event: #{ev.inspect}")
  begin
    d.(ev.class, ev)
  rescue X11::Error => e
    $logger.error(e.inspect)
  end
end
