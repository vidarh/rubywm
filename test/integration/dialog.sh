#!/usr/bin/env bash
#
# Integration test for dialog management (review §A5 / §C3). A
# _NET_WM_WINDOW_TYPE_DIALOG window must be *managed* — stored by the WM so it
# gains a stable identity, a _NET_CLIENT_LIST entry, and a place in
# _NET_CLIENT_LIST_STACKING — and floated (keeping its size) rather than tiled.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

count() { DISPLAY=$1 xprop -root "$2" 2>/dev/null | grep -oE '0x[0-9a-f]+' | wc -l | tr -d ' '; }
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
D=$($WMH status | awk '/display/{print $3}')

# Dialog on desktop 0 (the active desktop on monitor 0 at startup).
$WMH client ruby test/helpers/dialog_window.rb 0 >/dev/null 2>&1
sleep 1

check "dialog is in _NET_CLIENT_LIST"          "$(count "$D" _NET_CLIENT_LIST)"          "1"
check "dialog is in _NET_CLIENT_LIST_STACKING" "$(count "$D" _NET_CLIENT_LIST_STACKING)" "1"

# Floated, not tiled: it should keep (roughly) the 320x240 it asked for, not be
# shrunk into a tile. Find it and read its width.
wid=$($WMH tree 2>/dev/null | awk 'tolower($0) ~ /dialog/{print $1; exit}')
[ -n "$wid" ] || wid=$(DISPLAY=$D xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+' | head -1)
w=$(DISPLAY=$D xwininfo -id "$wid" 2>/dev/null | awk '/Width:/{print $2}')
check "dialog keeps its floated width (320)" "$w" "320"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
