#!/usr/bin/env bash
#
# Integration test for _NET_DESKTOP_NAMES (review §B6). The WM owns desktop
# identity and should publish the per-desktop names so pagers/docks can read
# them instead of writing their own.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
D=$($WMH status | awk '/display/{print $3}')

# xprop renders the property as: _NET_DESKTOP_NAMES(UTF8_STRING) = "1", "2", ...
names=$(DISPLAY=$D xprop -root _NET_DESKTOP_NAMES 2>/dev/null)
n=$(echo "$names" | grep -oE '"[^"]*"' | wc -l | tr -d ' ')
first=$(echo "$names" | grep -oE '"[^"]*"' | head -1 | tr -d '"')

check "publishes a name per desktop" "$n" "10"
check "default names are 1-based"    "$first" "1"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
