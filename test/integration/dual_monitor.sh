#!/usr/bin/env bash
#
# Integration test for the multi-monitor desktop swap (review §D3). Desktops can
# move freely between monitors: switching a monitor to a desktop already shown on
# another monitor swaps the two. Verifies the single-owner monitor<->desktop
# association keeps both monitors' _NET_CURRENT_DESKTOP_MONITOR_<n> correct.
#
# NB: --dual needs Xinerama heads, so this runs under Xephyr and opens a visible
# window (Xvfb can't fake dual heads). Not part of the headless default runner;
# run it explicitly: test/integration/dual_monitor.sh
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --dual --geom 800x600 >/dev/null 2>&1 || { echo "FAIL - dual harness failed to start"; exit 1; }
D=$($WMH status | awk '/display/{print $3}')
mon() { DISPLAY=$D xprop -root "_NET_CURRENT_DESKTOP_MONITOR_$1" 2>/dev/null | grep -oE '[0-9]+$'; }

# Startup: monitor 0 shows desktop 0, monitor 1 shows desktop 1.
# Put the pointer on monitor 0 and switch it to desktop 1 (live on monitor 1):
# the two desktops must swap.
DISPLAY=$D xdotool mousemove 200 300
$WMH msg _NET_CURRENT_DESKTOP 1 >/dev/null 2>&1; sleep 0.5

check "monitor 0 now shows desktop 1" "$(mon 0)" "1"
check "monitor 1 swapped to desktop 0" "$(mon 1)" "0"

# A floating window must follow its desktop when that desktop moves to another
# monitor (regression: floating windows reposition on show, so the desktop must
# be hidden/shown across the swap).
range() { # echoes "left" if X < 800, "right" if X >= 800
  local x; x=$(DISPLAY=$D xwininfo -id "$1" 2>/dev/null | awk '/Absolute upper-left X/{print $NF}')
  [ "$x" -lt 800 ] 2>/dev/null && echo left || echo right
}
DISPLAY=$D xdotool mousemove 200 300
$WMH msg _NET_CURRENT_DESKTOP 9 >/dev/null 2>&1; sleep 0.3   # floating desktop on monitor 0
$WMH client xclock >/dev/null 2>&1; sleep 1
fw=$($WMH tree 2>/dev/null | awk '/xclock/{print $1; exit}')
check "floating window starts on monitor 0" "$(range "$fw")" "left"

DISPLAY=$D xdotool mousemove 1200 300
$WMH msg _NET_CURRENT_DESKTOP 9 >/dev/null 2>&1; sleep 0.5   # move floating desktop to monitor 1
check "floating window follows desktop to monitor 1" "$(range "$fw")" "right"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
