#
# Optional Drb service. Primary use for now is for debugging
# as it avoids the trap context of ruby-debug
#

require 'drb/drb'
require 'drb/unix'

$uri="drbunix:#{ENV["HOME"]}/.rubywm"

def connect_to_server
  server = DRbObject.new_with_uri($uri)
  DRb.start_service
  server
end

def start_drb_service
  DRb.start_service($uri, $wm)
  STDERR.puts $uri
end
