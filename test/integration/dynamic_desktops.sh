#!/usr/bin/env bash
#
# Dynamic desktop lifecycle: stable keys, aligned metadata, idempotent ensure,
# per-monitor viewing, restart recovery, removal, and the standard EWMH count
# request.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
WMH=./test/wmh
fail=0

check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: expected '$3', got '$2'"
    fail=1
  fi
}
cleanup() { $WMH down >/dev/null 2>&1 || true; }
trap cleanup EXIT

root_cardinal() {
  DISPLAY="$D" xprop -root "$1" 2>/dev/null |
    sed -n 's/.* = //p' | cut -d, -f1 | tr -d ' '
}

quoted_count() {
  DISPLAY="$D" xprop -root "$1" 2>/dev/null |
    grep -oE '"[^"]*"' | wc -l | tr -d ' '
}

quoted_at() {
  DISPLAY="$D" xprop -root "$1" 2>/dev/null |
    grep -oE '"[^"]*"' | sed -n "$(($2 + 1))p" | tr -d '"'
}

cardinal_at() {
  DISPLAY="$D" xprop -root "$1" 2>/dev/null |
    sed -n 's/.* = //p' | tr -d ' ' | cut -d, -f"$(($2 + 1))"
}

$WMH down >/dev/null 2>&1 || true
$WMH up --geom 1280x800 >/dev/null 2>&1 || {
  echo "FAIL - harness failed to start"
  exit 1
}
D=$($WMH status | awk '/display/{print $3}')

generation_before=$(root_cardinal _RWM_DESKTOP_GENERATION)
duplicate_output=$(DISPLAY="$D" timeout 3 bundle exec ruby rubywm.rb 2>&1)
duplicate_status=$?
check "a second RubyWM exits instead of becoming a partial WM" \
  "$duplicate_status" "1"
check "duplicate startup reports the existing WM owner clearly" \
  "$(echo "$duplicate_output" |
     grep -q 'another window manager already owns display' && echo yes)" "yes"
check "rejected duplicate startup does not overwrite desktop state" \
  "$(root_cardinal _RWM_DESKTOP_GENERATION)" "$generation_before"

check "starts with configured desktop count" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"
check "publishes one stable key per desktop" \
  "$(quoted_count _RWM_DESKTOP_KEYS)" "10"
keys=$(DISPLAY="$D" xprop -root _RWM_DESKTOP_KEYS 2>/dev/null)
check "Workbench has a semantic stable key" \
  "$(echo "$keys" | grep -q '"workbench"' && echo yes)" "yes"
check "visible desktop 1 is an available reusable slot" \
  "$(cardinal_at _RWM_DESKTOP_FLAGS 0)" "48"
check "configured Todo desktop 2 is reserved" \
  "$(cardinal_at _RWM_DESKTOP_FLAGS 1)" "1"
check "configured Workbench desktop 10 is reserved and a group root" \
  "$(cardinal_at _RWM_DESKTOP_FLAGS 9)" "15"

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb ensure project:rubywm \
  --name RubyWM --project "$PWD" --group Coding --mode floating --view)
created=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["created"]' "$reply")
leased=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["leased"]' "$reply")
check "ensure creates a desktop" "$created" "true"
check "ensure leases an initial slot" "$leased" "true"
check "leasing preserves EWMH desktop count" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"
check "ensure skips visible desktop 1 and configured desktop 2" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "2"
check "leased slot publishes its project key at desktop 3" \
  "$(quoted_at _RWM_DESKTOP_KEYS 2)" "project:rubywm"
check "leased slot is occupied but remembers its slot origin" \
  "$(cardinal_at _RWM_DESKTOP_FLAGS 2)" "16"
check "current exposes the active project's working directory" \
  "$(DISPLAY="$D" bundle exec ruby rwmctl.rb current --field pwd)" "$PWD"
check "current exposes the active stable key" \
  "$(DISPLAY="$D" bundle exec ruby rwmctl.rb current --field key)" \
  "project:rubywm"

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb edit project:rubywm \
  --name Edited --pwd "$PWD")
updated=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["updated"]' "$reply")
check "edit updates an existing project without recreating it" \
  "$updated/$(quoted_at _NET_DESKTOP_NAMES 2)" "true/Edited"
count_before_missing_edit=$(root_cardinal _NET_NUMBER_OF_DESKTOPS)
if DISPLAY="$D" bundle exec ruby rwmctl.rb edit project:missing \
  --name Missing >/dev/null 2>&1; then
  missing_edit_protected=no
else
  missing_edit_protected=yes
fi
check "edit refuses a missing key instead of creating a typo" \
  "$missing_edit_protected/$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" \
  "yes/$count_before_missing_edit"

$WMH client xterm -e 'sleep 600' >/dev/null 2>&1
wid=$($WMH tree 2>/dev/null | awk '/xterm/{print $1; exit}')
[ -n "$wid" ] || {
  echo "FAIL - could not find project xterm"
  exit 1
}
check "desktop occupancy is published for Rebar" \
  "$(cardinal_at _RWM_DESKTOP_CLIENT_COUNTS 2)" "1"

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb ensure project:rubywm \
  --name Ignored)
created=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["created"]' "$reply")
updated=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["updated"]' "$reply")
check "ensure is idempotent by stable key" "$created" "false"
check "ensure can refresh an existing display name" "$updated" "true"
last_name=$(quoted_at _NET_DESKTOP_NAMES 2)
check "refreshed name is published through EWMH" "$last_name" "Ignored"
check "idempotent ensure does not grow the list" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"

$WMH restart >/dev/null 2>&1 || {
  echo "FAIL - rubywm failed to restart"
  exit 1
}
check "dynamic desktop survives WM restart" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"
keys=$(DISPLAY="$D" xprop -root _RWM_DESKTOP_KEYS 2>/dev/null)
check "stable key survives WM restart" \
  "$(echo "$keys" | grep -q '"project:rubywm"' && echo yes)" "yes"
check "visible project survives WM restart" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "2"
check "project client keeps its desktop across restart" \
  "$(DISPLAY="$D" xprop -id "$wid" _NET_WM_DESKTOP 2>/dev/null |
     grep -oE '[0-9]+$')" "2"

if DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:rubywm \
  >/dev/null 2>&1; then
  nonempty_protected=no
else
  nonempty_protected=yes
fi
check "non-empty dynamic desktop is protected" "$nonempty_protected" "yes"

DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:rubywm \
  --force --fallback desktop-1 >/dev/null
check "forced removal moves clients and releases the slot" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"
check "forced removal republishes client fallback index" \
  "$(DISPLAY="$D" xprop -id "$wid" _NET_WM_DESKTOP 2>/dev/null |
     grep -oE '[0-9]+$')" "0"
check "occupancy follows a client moved to an unnamed desktop" \
  "$(cardinal_at _RWM_DESKTOP_CLIENT_COUNTS 0)/$(cardinal_at _RWM_DESKTOP_CLIENT_COUNTS 2)" \
  "1/0"
check "release restores desktop 3's base key" \
  "$(quoted_at _RWM_DESKTOP_KEYS 2)" "desktop-3"
check "release restores desktop 3's numeric name" \
  "$(quoted_at _NET_DESKTOP_NAMES 2)" "3"
check "release makes desktop 3 available again" \
  "$(cardinal_at _RWM_DESKTOP_FLAGS 2)" "48"

# Claim the currently visible empty address in place, then exercise the same
# add/re-key lifecycle used by Rebar's top-bar "+".
$WMH msg _RWM_VIEW_GROUP 3 >/dev/null
sleep 0.2
reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb edit current \
  --key project:scratch --name Scratch --pwd . --group Scratch)
check "edit current claims and re-keys the visible empty desktop" \
  "$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["key"]' "$reply")/$(root_cardinal _NET_CURRENT_DESKTOP)/$(cardinal_at _RWM_DESKTOP_FLAGS 2)" \
  "project:scratch/2/16"
check "claimed desktop publishes its new group and working directory" \
  "$(quoted_at _RWM_DESKTOP_GROUPS 2)/$(quoted_at _RWM_DESKTOP_PROJECTS 2)" \
  "Scratch/$PWD"

$WMH msg _RWM_ADD_GROUP_VIEW 1 >/dev/null
sleep 0.2
check "top-bar add appends and selects a tiled view in the current group" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)/$(root_cardinal _NET_CURRENT_DESKTOP)/$(quoted_at _RWM_DESKTOP_GROUPS 10)/$(cardinal_at _RWM_DESKTOP_MODES 10)" \
  "11/10/Scratch/0"
check "new group view inherits the project's working directory" \
  "$(DISPLAY="$D" bundle exec ruby rwmctl.rb current --field pwd)" "$PWD"

DISPLAY="$D" bundle exec ruby rwmctl.rb edit current \
  --key project:scratch:tools --name Tools >/dev/null
DISPLAY="$D" bundle exec ruby rwmctl.rb edit current \
  --rekey-group Experiments >/dev/null
check "edit current can re-key the view and its whole group" \
  "$(quoted_at _RWM_DESKTOP_KEYS 10)/$(quoted_at _RWM_DESKTOP_GROUPS 2)/$(quoted_at _RWM_DESKTOP_GROUPS 10)" \
  "project:scratch:tools/Experiments/Experiments"

DISPLAY="$D" bundle exec ruby rwmctl.rb view project:scratch
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:scratch:tools >/dev/null
$WMH msg _RWM_VIEW_GROUP 1 >/dev/null
sleep 0.2
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:scratch >/dev/null
check "removing the temporary group restores the numeric placeholder" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)/$(quoted_at _RWM_DESKTOP_KEYS 2)/$(cardinal_at _RWM_DESKTOP_FLAGS 2)" \
  "10/desktop-3/48"

if DISPLAY="$D" bundle exec ruby rwmctl.rb remove desktop-1 >/dev/null 2>&1; then
  protected=no
else
  protected=yes
fi
check "configured desktops are protected" "$protected" "yes"

DISPLAY="$D" bundle exec ruby rwmctl.rb count 12
sleep 0.2
check "standard count request expands desktop list" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "12"
DISPLAY="$D" bundle exec ruby rwmctl.rb count 10
sleep 0.2
check "standard count request removes dynamic tail" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb ensure project:rubywm \
  --name RubyWM --group Coding)
leased=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["leased"]' "$reply")
check "the first Coding project leases numeric address 3" \
  "$leased/$(quoted_at _RWM_DESKTOP_KEYS 2)" "true/project:rubywm"

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb ensure project:improve \
  --name Improve --group Coding)
leased=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["leased"]' "$reply")
check "a second Coding project uses an overflow backing desktop" \
  "$leased/$(root_cardinal _NET_NUMBER_OF_DESKTOPS)/$(quoted_at _RWM_DESKTOP_KEYS 10)" \
  "false/11/project:improve"
check "secondary Coding project does not consume numeric address 5" \
  "$(quoted_at _RWM_DESKTOP_KEYS 4)/$(cardinal_at _RWM_DESKTOP_FLAGS 4)" \
  "desktop-5/48"

$WMH msg _RWM_VIEW_GROUP 3 >/dev/null
sleep 0.2
check "group address 3 enters Coding" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "2"
DISPLAY="$D" bundle exec ruby rwmctl.rb view next
sleep 0.2
check "Coding can select its overflow child" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "10"
$WMH msg _RWM_VIEW_GROUP 5 >/dev/null
sleep 0.2
check "group address 5 still opens its empty numeric desktop" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)/$(quoted_at _RWM_DESKTOP_KEYS 4)" \
  "4/desktop-5"
$WMH msg _RWM_VIEW_GROUP 3 >/dev/null
sleep 0.2
check "returning to Coding restores its overflow MRU child" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "10"
$WMH msg _RWM_VIEW_GROUP 1 >/dev/null
sleep 0.2

for n in $(seq 1 6); do
  DISPLAY="$D" bundle exec ruby rwmctl.rb ensure "project:pool-$n" \
    --name "Pool $n" --group "Group $n" >/dev/null
done
check "six new groups consume the remaining numeric addresses 4 through 9" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "11"
reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb ensure project:overflow \
  --name Overflow --group Overflow)
leased=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["leased"]' "$reply")
check "ensure appends only after the reusable pool is exhausted" \
  "$leased/$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "false/12"
DISPLAY="$D" bundle exec ruby rwmctl.rb ensure project:novelator \
  --name Novelator --group Novelator >/dev/null
check "a second overflow group is desktop 13" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "13"

$WMH restart >/dev/null 2>&1 || {
  echo "FAIL - rubywm failed to restart with appended desktops"
  exit 1
}
check "restart preserves child and overflow backing numbering" \
  "$(quoted_at _RWM_DESKTOP_KEYS 10)/$(quoted_at _RWM_DESKTOP_KEYS 11)/$(quoted_at _RWM_DESKTOP_KEYS 12)" \
  "project:improve/project:overflow/project:novelator"

$WMH msg _RWM_VIEW_GROUP 3 >/dev/null
sleep 0.2
check "group MRU survives RubyWM restart" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "10"
DISPLAY="$D" bundle exec ruby rwmctl.rb group previous
sleep 0.2
check "semantic group cycling follows the high-level order" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "1"
$WMH msg _RWM_VIEW_GROUP 3 >/dev/null
sleep 0.2
check "returning to a group restores its most recently used project" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "10"
DISPLAY="$D" bundle exec ruby rwmctl.rb group previous
sleep 0.2

# Return desktops 4 and 5 to the pool, then explicitly renumber the two
# appended groups into them. The first move leaves an internal placeholder;
# the second lets both empty tail placeholders be trimmed.
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:pool-1 >/dev/null
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:pool-2 >/dev/null
DISPLAY="$D" bundle exec ruby rwmctl.rb view project:overflow
sleep 0.2
$WMH client xterm -T move-source -e 'sleep 600' >/dev/null 2>&1
move_wid=$($WMH tree 2>/dev/null | awk '/move-source/{print $1; exit}')
[ -n "$move_wid" ] || {
  echo "FAIL - could not find renumbered project xterm"
  exit 1
}

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb move Overflow --first)
number=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["number"]' "$reply")
check "move --first renumbers an appended group to desktop 4" \
  "$number/$(quoted_at _RWM_DESKTOP_KEYS 3)" "4/project:overflow"
check "visible monitor follows the renumbered desktop" \
  "$(root_cardinal _NET_CURRENT_DESKTOP)" "3"
check "project windows follow the renumbered desktop" \
  "$(DISPLAY="$D" xprop -id "$move_wid" _NET_WM_DESKTOP 2>/dev/null |
     grep -oE '[0-9]+$')" "3"
check "occupied child and later group keep the count temporarily at 13" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "13"

reply=$(DISPLAY="$D" bundle exec ruby rwmctl.rb move Novelator --to 5)
number=$(ruby -rjson -e 'puts JSON.parse(ARGV[0])["number"]' "$reply")
check "move --to uses the one-based Rebar desktop number" \
  "$number/$(quoted_at _RWM_DESKTOP_KEYS 4)" "5/project:novelator"
check "moving final groups trims placeholders but retains Coding child tail" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "11"

DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:overflow \
  --force --fallback desktop-1 >/dev/null
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:novelator >/dev/null
for n in $(seq 3 6); do
  DISPLAY="$D" bundle exec ruby rwmctl.rb remove "project:pool-$n" >/dev/null
done
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:improve >/dev/null
DISPLAY="$D" bundle exec ruby rwmctl.rb remove project:rubywm >/dev/null
check "cleanup deletes the appended view and releases leased slots" \
  "$(root_cardinal _NET_NUMBER_OF_DESKTOPS)" "10"

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAILURES"; fi
exit $fail
