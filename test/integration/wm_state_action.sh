#!/usr/bin/env bash
#
# Integration test for _NET_WM_STATE action handling (review §B7). The WM must
# honour the add/remove/toggle action (not blindly toggle), reflect the state
# in the window's _NET_WM_STATE property, and distinguish fullscreen from
# maximize (vert+horz).
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
GEOM=1280x800
fail=0

check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
has()   { if echo "$2" | grep -q "$3"; then echo "ok   - $1"; else echo "FAIL - $1: '$3' not in '$2'"; fail=1; fi; }
hasnot(){ if echo "$2" | grep -q "$3"; then echo "FAIL - $1: '$3' unexpectedly in '$2'"; fail=1; else echo "ok   - $1"; fi; }
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
state() { DISPLAY=$D xprop -id "$wid" _NET_WM_STATE 2>/dev/null; }

before=$(width)

# ADD fullscreen, then ADD again: must stay fullscreen (the old toggle-only
# code would have un-fullscreened on the second ADD).
$WMH msg -w "$wid" _NET_WM_STATE 1 _NET_WM_STATE_FULLSCREEN 0 1 >/dev/null 2>&1; sleep 0.4
check "ADD fullscreen fills monitor width" "$(width)" "${GEOM%x*}"
has   "ADD fullscreen sets property"        "$(state)" "_NET_WM_STATE_FULLSCREEN"
$WMH msg -w "$wid" _NET_WM_STATE 1 _NET_WM_STATE_FULLSCREEN 0 1 >/dev/null 2>&1; sleep 0.4
check "second ADD is idempotent"            "$(width)" "${GEOM%x*}"

# REMOVE fullscreen restores size and clears the property.
$WMH msg -w "$wid" _NET_WM_STATE 0 _NET_WM_STATE_FULLSCREEN 0 1 >/dev/null 2>&1; sleep 0.4
check  "REMOVE fullscreen restores width" "$(width)" "$before"
hasnot "REMOVE fullscreen clears property" "$(state)" "_NET_WM_STATE_FULLSCREEN"

# Maximize (vert+horz) publishes both maximize atoms.
$WMH msg -w "$wid" _NET_WM_STATE 1 _NET_WM_STATE_MAXIMIZED_VERT _NET_WM_STATE_MAXIMIZED_HORZ 1 >/dev/null 2>&1; sleep 0.4
has "maximize sets vert atom" "$(state)" "_NET_WM_STATE_MAXIMIZED_VERT"
has "maximize sets horz atom" "$(state)" "_NET_WM_STATE_MAXIMIZED_HORZ"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
