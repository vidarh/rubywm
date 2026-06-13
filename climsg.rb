#!/bin/env ruby

$: << __dir__
require 'vendor/bundler/setup'
require 'X11'
require 'pp'

dpy = X11::Display.new

if ARGV[0] == "-w"
  ARGV.shift
  wname = ARGV.shift
  if wname == "focused"
    win = dpy.get_input_focus
  else
    win = Integer(wname) rescue nil
  end
  if !win
    $stderr.puts "ERROR: #{wname} should be an integer window id or 'focused'"
    exit 1
  end
end

if ARGV.empty?
  STDERR.puts "ERROR: An Atom / string name of message type to send is required"
  exit(1)
end

data = ARGV[1..-1]&.map do |arg|
  item = Integer(arg) rescue nil
  item ||= dpy.atom(arg)
  if item.nil?
    puts "ERROR: Argument '#{arg}' is not an integer and can't be converted to an Atom"
    exit(2)
  end
  item
end || []

msg = {
  mask: X11::Form::SubstructureNotifyMask | X11::Form::SubstructureRedirectMask,
  type: ARGV[0],
  data: data
}
msg[:window] = win.focus if win

dpy.client_message(**msg)

  
