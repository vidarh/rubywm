#!/usr/bin/env bash
#
# Integration test for desktop-window confinement (review §H). A
# _NET_WM_WINDOW_TYPE_DESKTOP window pinned to desktop 5 must:
#   * stay on desktop 5 (never reassigned to the active desktop),
#   * be hidden (offscreen) while desktop 5 is inactive,
#   * fill the monitor when desktop 5 is active.
# Regression guard for FloatingLayout#place reassigning the desktop.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

check()    { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
check_ge() { if [ "$2" -ge "$3" ] 2>/dev/null; then echo "ok   - $1"; else echo "FAIL - $1: '$2' not >= '$3'"; fail=1; fi; }
cleanup()  { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
$WMH client ruby test/helpers/desktop_window.rb 5 >/dev/null 2>&1   # pin to desktop 5
sleep 1.2

D=$($WMH status | awk '/display/{print $3}')
wid=$(DISPLAY=$D xdotool search --all --maxdepth 2 --name '' 2>/dev/null | while read w; do
  DISPLAY=$D xprop -id "$w" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q DESKTOP && { echo "$w"; break; }
done)
[ -n "$wid" ] || { echo "FAIL - could not find desktop window"; exit 1; }

xpos() { DISPLAY=$D xwininfo -id "$wid" 2>/dev/null | awk '/Absolute upper-left X/{print $NF}'; }
width() { DISPLAY=$D xwininfo -id "$wid" 2>/dev/null | awk '/Width:/{print $2; exit}'; }

check    "stays pinned to desktop 5"        "$(DISPLAY=$D xprop -id "$wid" _NET_WM_DESKTOP 2>/dev/null | grep -oE '[0-9]+$')" "5"
check_ge "offscreen while desktop inactive" "$(xpos)" "10000"

$WMH msg _NET_CURRENT_DESKTOP 5 >/dev/null 2>&1; sleep 0.5
check "onscreen when its desktop is active" "$(xpos)" "0"
check "fills the monitor width"             "$(width)" "1280"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
