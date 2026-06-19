#!/usr/bin/env bash
#
# Integration test for ICCCM WM_STATE (review §B3): a managed window reads
# Normal while shown and Iconic while on an inactive desktop.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

state() { DISPLAY=$1 xprop -id "$2" WM_STATE 2>/dev/null | awk -F': ' '/window state/{print $2}'; }
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
$WMH msg _NET_CURRENT_DESKTOP 9 >/dev/null 2>&1   # desktop 10 = floating
$WMH client xterm -e 'sleep 600' >/dev/null 2>&1
sleep 1

D=$($WMH status | awk '/display/{print $3}')
wid=$($WMH tree 2>/dev/null | awk '/xterm/{print $1; exit}')
[ -n "$wid" ] || { echo "FAIL - could not find xterm window"; exit 1; }

check "Normal while shown" "$(state "$D" "$wid")" "Normal"
$WMH msg _NET_CURRENT_DESKTOP 0 >/dev/null 2>&1; sleep 0.4
check "Iconic while on inactive desktop" "$(state "$D" "$wid")" "Iconic"
$WMH msg _NET_CURRENT_DESKTOP 9 >/dev/null 2>&1; sleep 0.4
check "Normal again after returning" "$(state "$D" "$wid")" "Normal"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
