#!/usr/bin/env bash
#
# Integration test for window closing (review §B4). _NET_CLOSE_WINDOW should
# close the target window via WM_DELETE_WINDOW (xterm supports the protocol),
# and the WM should drop it from _NET_CLIENT_LIST.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

clients() { DISPLAY=$1 xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+' | wc -l | tr -d ' '; }
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

check "one managed client before close" "$(clients "$D")" "1"
$WMH msg -w "$wid" _NET_CLOSE_WINDOW >/dev/null 2>&1
sleep 0.8
check "client gone after _NET_CLOSE_WINDOW" "$(clients "$D")" "0"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
