#!/usr/bin/env bash
#
# Integration test for managed docks + struts / work area (review §B5/§B2).
# A _NET_WM_WINDOW_TYPE_DOCK bottom bar with _NET_WM_STRUT_PARTIAL must:
#   * shrink _NET_WORKAREA by the reserved height,
#   * keep tiled windows out of the reserved strip,
#   * stay visible across desktop switches (docks are sticky).
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

check()    { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
check_le() { if [ "$2" -le "$3" ] 2>/dev/null; then echo "ok   - $1"; else echo "FAIL - $1: '$2' not <= '$3'"; fail=1; fi; }
cleanup()  { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
D=$($WMH status | awk '/display/{print $3}')

wa_h() { DISPLAY=$D xprop -root _NET_WORKAREA 2>/dev/null | sed 's/.*= //' | cut -d, -f4 | tr -d ' '; }

check "full work area before dock" "$(wa_h)" "800"

$WMH client ruby test/helpers/dock_window.rb 40 >/dev/null 2>&1
sleep 1.2
check "work area shrinks by the strut" "$(wa_h)" "760"

# A tiled window must stay above the reserved strip.
$WMH msg _NET_CURRENT_DESKTOP 0 >/dev/null 2>&1
$WMH client xterm -e 'sleep 600' >/dev/null 2>&1
sleep 1
xt=$(DISPLAY=$D xdotool search --class xterm 2>/dev/null | head -1)
bottom=$(DISPLAY=$D xwininfo -id "$xt" 2>/dev/null | awk '/Absolute upper-left Y/{y=$NF}/Height:/{h=$2}END{print y+h}')
check_le "tiled window stays above the bar" "$bottom" "760"

# The dock stays mapped when switching desktops.
dock=$(DISPLAY=$D xdotool search --all --maxdepth 2 --name '' 2>/dev/null | while read w; do
  DISPLAY=$D xprop -id "$w" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q DOCK && { echo "$w"; break; }
done)
$WMH msg _NET_CURRENT_DESKTOP 3 >/dev/null 2>&1; sleep 0.4
mapstate=$(DISPLAY=$D xwininfo -id "$dock" 2>/dev/null | awk -F': ' '/Map State/{print $2}')
check "dock stays visible across desktops" "$mapstate" "IsViewable"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
