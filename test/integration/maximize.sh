#!/usr/bin/env bash
#
# Integration test for fullscreen/maximize toggle and restore (review §A3).
# A floating window on desktop 10 is maximized to fill the monitor via a
# _NET_WM_STATE_FULLSCREEN ClientMessage, then restored. Regression guard for
# the @realgeom typo that left windows stuck maximized.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
GEOM=1280x800
fail=0

check() { # name actual expected
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi
}
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom "$GEOM" >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
$WMH msg _NET_CURRENT_DESKTOP 9 >/dev/null 2>&1   # desktop 10 = floating
$WMH client xclock >/dev/null 2>&1
sleep 1

D=$($WMH status | awk '/display/{print $3}')
wid=$($WMH tree 2>/dev/null | awk '/xclock/{print $1; exit}')
[ -n "$wid" ] || { echo "FAIL - could not find xclock window"; exit 1; }

width() { DISPLAY=$D xwininfo -id "$wid" 2>/dev/null | awk '/Width:/{print $2; exit}'; }

before=$(width)
$WMH msg -w "$wid" _NET_WM_STATE 2 _NET_WM_STATE_FULLSCREEN 0 1 >/dev/null 2>&1; sleep 0.4
maxed=$(width)
$WMH msg -w "$wid" _NET_WM_STATE 2 _NET_WM_STATE_FULLSCREEN 0 1 >/dev/null 2>&1; sleep 0.4
restored=$(width)

check "maximize fills monitor width" "$maxed"    "${GEOM%x*}"
check "restore returns to prior size" "$restored" "$before"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
