#!/usr/bin/env bash
#
# Integration test for EWMH compliance advertising (review §B1):
# _NET_SUPPORTING_WM_CHECK (root + self-referential on the child window) and
# _NET_SUPPORTED on the root.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi; }
present() { if [ -n "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1: empty"; fail=1; fi; }
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }
D=$($WMH status | awk '/display/{print $3}')

root_chk=$(DISPLAY=$D xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -oE '0x[0-9a-f]+')
present "root has _NET_SUPPORTING_WM_CHECK" "$root_chk"

self_chk=$(DISPLAY=$D xprop -id "$root_chk" _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -oE '0x[0-9a-f]+')
check "check window references itself" "$self_chk" "$root_chk"

supported=$(DISPLAY=$D xprop -root _NET_SUPPORTED 2>/dev/null | grep -oc '_NET_SUPPORTING_WM_CHECK')
check "_NET_SUPPORTED advertised" "$( [ "$supported" -ge 1 ] && echo yes )" "yes"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
