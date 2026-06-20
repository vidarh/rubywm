#!/usr/bin/env bash
#
# Integration test for _RWM_DESKTOP_WINDOW_DESKTOP (review §H2). The WM reads
# the `desktop: true` config flag and publishes which desktop hosts
# desktop-type windows, so the desktop client reads it instead of hardcoding.
# config.yml flags desktop 10 (index 9).
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

host=$(DISPLAY=$D xprop -root _RWM_DESKTOP_WINDOW_DESKTOP 2>/dev/null | grep -oE '[0-9]+$')
check "publishes the configured host desktop" "$host" "9"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
