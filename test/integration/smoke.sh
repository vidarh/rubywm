#!/usr/bin/env bash
#
# Integration smoke test: boots RubyWM under the harness (headless Xvfb) and
# asserts the stable, observable EWMH contract. Requires Xvfb + the harness.
#
# Exits non-zero on any failure. Safe: runs only on the harness's private
# display, never :0.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

prop() { $WMH props 2>/dev/null | awk -F'= ' "/$1\\(/{print \$2; exit}"; }
check() { # name actual expected
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1: expected '$3', got '$2'"; fail=1; fi
}

cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || { echo "FAIL - harness failed to start"; exit 1; }

check "advertises 10 desktops" "$(prop _NET_NUMBER_OF_DESKTOPS)" "10"
check "starts on desktop 0"     "$(prop _NET_CURRENT_DESKTOP)"    "0"

$WMH msg _NET_CURRENT_DESKTOP 3 >/dev/null 2>&1
check "switch to desktop 3"     "$(prop _NET_CURRENT_DESKTOP)"    "3"

$WMH msg _NET_CURRENT_DESKTOP 0 >/dev/null 2>&1
check "switch back to desktop 0" "$(prop _NET_CURRENT_DESKTOP)"   "0"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
