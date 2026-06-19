#!/usr/bin/env bash
#
# Integration test for ConfigureRequest handling (review §A1). With
# SubstructureRedirect held by the WM, a client's self-resize is dropped unless
# the WM honours it. A floating window must be allowed to size itself.
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
$WMH msg _NET_CURRENT_DESKTOP 9 >/dev/null 2>&1   # desktop 10 = floating
$WMH client xclock >/dev/null 2>&1
sleep 1

D=$($WMH status | awk '/display/{print $3}')
wid=$($WMH tree 2>/dev/null | awk '/xclock/{print $1; exit}')
[ -n "$wid" ] || { echo "FAIL - could not find xclock window"; exit 1; }

DISPLAY=$D xdotool windowsize "$wid" 500 300
sleep 0.4
size=$(DISPLAY=$D xwininfo -id "$wid" 2>/dev/null | awk '/Width:/{w=$2}/Height:/{h=$2}END{print w"x"h}')
check "floating window may resize itself" "$size" "500x300"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
