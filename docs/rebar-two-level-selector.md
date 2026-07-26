# Rebar two-level selector plan

Status: implemented and verified under Xvfb, 2026-07-25. Final visual sizing on
the production monitors remains user-adjustable through the font and
`PROJECT_BAR` mode.

## 1. Correction and hard constraints

The first Rebar patch made a flat dynamic list fit by discarding information:
it prefixed project names with their group, truncated the result, and exposed
only a moving slice of one long list. That is not a two-level selector and it
does not meet the usability requirement.

The replacement must obey these constraints:

- The existing 40-pixel Rebar cannot contain two readable rows at its current
  font size.
- The existing bottom bar remains the high-level selector.
- Project/view selection belongs in a separate window, not a compressed second
  row inside Rebar.
- A tab displays its useful name in full. It never turns `RubyWM` into
  `Coding/...`.
- Group names are not repeated on every project tab.
- Text is rendered once. There is no offset black copy, drop shadow, glow, or
  faux outline.
- The flat EWMH desktop list remains the compatibility model. Hierarchy is
  metadata and presentation, not a second hidden workspace implementation.
- The configured initial desktop count is a fixed set of keyboard-addressable
  high-level addresses, not ten permanently occupied contexts.
- The first project in a new group may lease an unused implicit address.
  Additional projects in that group use overflow EWMH desktops; they never
  consume another numeric address.

The implementation replaces the rejected flat presentation while retaining its
coherent protocol-reading work. Hierarchy/model, viewport rendering, bottom
switcher, and top dock are separate classes.

## 2. User-facing model

There are three distinct concepts:

```text
high-level context       project             view
──────────────────       ─────────────       ──────────────
Coding                   RubyWM              main
                                             tools
                         Compiler            main
Art                      Cover 2026           canvas
                                             palettes
Workbench                —                   desktop
```

Every view is still one ordinary EWMH desktop. Rebar presents those flat
desktops through two selectors:

1. The existing bottom Rebar selects a high-level context.
2. A separate top project strip selects the views inside the active context.

For the first implementation, a project with one view can use the view's
display name directly. Multiple views of one project may use labels such as
`main` and `tools`; the project name can be a fixed section label or appear
only where needed to disambiguate.

## 3. Stable hierarchy metadata

The current `group` value is not sufficient if it is merely a display label.
The hierarchy needs a stable key and an explicit root.

Use the existing aligned desktop arrays, with these semantics:

- `key`: stable identity of this EWMH desktop/view.
- `group`: stable key of its high-level parent.
- `name`: the label for this view.
- `project`: stable project identity, empty for a context root or non-project
  view.
- `flags` bit 3: this desktop is the root/default view for its group.
- `flags` bit 4: this desktop originated as a reusable numeric slot.
- `flags` bit 5: that reusable slot is currently an available placeholder.
- `client count`: number of managed windows currently assigned to the
  desktop, published in the aligned `_RWM_DESKTOP_CLIENT_COUNTS` array.

The flag allocation becomes:

```text
bit 0  configured/static desktop
bit 1  pinned desktop
bit 2  desktop-window host
bit 3  group root/default view
bit 4  slot-backed desktop
bit 5  available placeholder
```

`desktops.number` creates the initial EWMH slots and therefore preserves
`Super+1..0`, but it does not make every one of those slots configured/static:

- A numbered entry actually present in `config.yml` is explicitly configured
  and reserved. Desktop 2 with its Todo layout and desktop 10 with Workbench
  are examples, even if desktop 2 has no `name`.
- A desktop created only to satisfy `desktops.number` is an implicit,
  reusable placeholder. It starts with bits 4 and 5 set.
- Leasing a placeholder clears bit 5 but retains bit 4. This records that
  removal must later restore the slot rather than delete and reindex it.
- An appended dynamic desktop has neither bit 4 nor bit 5.
- A visible placeholder is temporarily in use and cannot be leased, even
  though bit 5 remains set.

This distinction must be represented in the published metadata and the
restart snapshot. It must not be inferred from a numeric-looking name.

### Leasing an initial slot

When `ensure` creates the first project in a group, it scans desktops in
current EWMH/index order and leases the first desktop satisfying all of these
conditions:

```text
available-placeholder flag is set
not visible on any monitor
contains no managed client windows
not explicitly configured/static
not pinned
not a desktop-window host
```

All managed clients count, including currently unmapped or WM-hidden clients.
An already leased project remains occupied even if it has no windows, because
the stable project view continues to exist until explicitly removed.

For the present configuration, if desktop 1 is visible, desktop 2 is reserved
for Todo, and desktop 10 is reserved for Workbench, the first Coding project
leases desktop 3. `_NET_NUMBER_OF_DESKTOPS` remains 10 and `Super+3` becomes
Coding's stable address. If desktop 3 is visible or contains a window, the scan
continues with desktop 4. A second Coding project does not repeat that scan: it
is appended as an overflow backing desktop even if desktop 5 is empty. The
next newly created group may still lease desktop 5. Only a group's first
project can establish a new numeric address.

The resulting presentation is:

| EWMH desktop | State after `ensure RubyWM --group coding` | Selector |
|---|---|---|
| 1 | visible implicit placeholder | bottom: `1` |
| 2 | explicit Todo desktop, unnamed | bottom: `2` |
| 3 | leased by project `RubyWM` | bottom: `3: Coding`; top: `RubyWM` |
| 4–9 | available implicit placeholders | hidden |
| 10 | explicit Workbench desktop | bottom: `10: System` |

This is how the project model replaces the unused fixed-layout entries without
breaking the existing numeric shortcuts.

Ensuring `Improve` in the same Coding group then appends EWMH desktop 11.
Rebar adds `Improve` only to Coding's top project strip; the bottom contexts
and the availability of addresses 4–9 do not change.

Leasing is an in-place conversion of an empty `Desktop` object:

- keep its current EWMH index;
- set the requested stable key, name, project, group, and layout mode;
- clear the available-placeholder flag but retain the slot-backed flag;
- replace the placeholder layout with the requested fresh empty layout;
- publish the complete standard/custom arrays, then generation.

Generic `_NET_NUMBER_OF_DESKTOPS` expansion creates additional anonymous
available slots. A shrink may discard trailing available placeholders, but it
must not silently remove a configured, visible, non-empty, or leased desktop.

### Restart and release

A group's one leased slot is restored at the same index after a normal RubyWM
restart. The slot-backed flag prevents startup from also inserting a new
implicit placeholder for that position. Existing appended project desktops
also retain their indices: startup does not silently reorder a valid layout.
Configured entries remain authoritative at explicitly reserved indices.

Snapshots written by the earlier allocator may contain two or more
slot-backed projects from the same group. Startup repairs that invalid state:
it keeps the group's first/root numeric address, moves each secondary project
to the overflow tail, remaps its windows, monitor selection, and MRU history,
and restores the vacated numeric placeholders. This one-time migration is why
an existing session must restart RubyWM after upgrading.

Renumbering is an explicit operation:

```sh
rwmctl move Coding --first
rwmctl move Novelator --to 4
```

`--first` chooses the first empty, non-visible, non-reserved reusable slot.
`--to` takes the one-based desktop number shown by Rebar. The complete Desktop
object moves, so its windows, layout, monitor ownership, stable key, and
metadata move atomically. Empty placeholders left at the end are trimmed once
no later dynamic desktop requires them. A move into the fixed numeric pool is
rejected when another project in the same group already owns a numeric
address.

Removing a slot-backed project restores the slot in place:

- ordinary removal still refuses a visible or non-empty desktop;
- forced removal first moves clients to the explicit fallback;
- restore the base key/name for that numeric position;
- clear project/group/group-root metadata;
- recreate the default tiled layout;
- set both slot-backed and available-placeholder flags;
- do not decrement the count or reindex later desktops.

Removing an appended dynamic desktop retains the existing safe
delete-and-reindex behavior. This makes `remove` mean “return the keyboard slot
to the pool” when the view was leased and “remove the extra EWMH desktop” when
it was appended.

Example configuration:

```yaml
desktops:
  number: 10

  1:
    key: coding
    name: Coding
    group: coding
    group_root: true

  10:
    key: workbench
    name: Workbench
    group: workbench
    group_root: true
    layout: floating
    desktop: true
    pinned: true
```

Example dynamic views:

```sh
rwmctl ensure project:rubywm:main \
  --name RubyWM \
  --project /src/rubywm \
  --group coding

rwmctl ensure project:rubywm:tools \
  --name tools \
  --project /src/rubywm \
  --group coding \
  --mode floating
```

Compatibility rules:

- An ungrouped configured desktop is a singleton high-level context whose key
  and label come from that desktop.
- An available placeholder is omitted from both selectors only while it is
  empty and inactive. A visible or occupied unnamed placeholder appears as its
  desktop number once, so Rebar never hides the user's current context or a
  desktop containing windows.
- If a group has children but no explicit root, Rebar may synthesize a
  temporary parent from the group key. This is a migration fallback, not the
  preferred configuration.
- Group order follows the configured root desktops. Synthetic groups follow in
  first-seen order.
- View order follows the flat EWMH order initially. A separate order field is
  unnecessary until real use demonstrates a need.

## 4. Bottom bar: high-level contexts only

The existing Rebar window remains 40 pixels high and remains at its current
edge. It no longer displays every flat EWMH desktop.

It displays:

- one button per explicit group root;
- one button per ungrouped singleton desktop;
- a synthetic group button only during migration.
- one temporary numeric button if an otherwise hidden placeholder is currently
  visible on this monitor.

The label is the group's keyboard address followed by its group name, for
example `3: Coding`, `7: Art`, or `10: System`. An explicit root supplies the
address; a synthetic migration group uses its first EWMH member. It is never
assembled as `group/name`.

All fallback labels pass through one normalization rule. For user-visible
desktop number `n`:

```text
blank or whitespace-only name  -> n
name exactly equal to n        -> n
any other name                 -> n: name   (legacy flat/singleton display)
```

Bottom group tabs and named singleton desktops retain their numeric keyboard
address. Top project/view tabs display only their meaningful name. In
particular, the default EWMH name `"1"` is displayed as `1`, never `1: 1`.

Clicking a high-level button:

1. selects that group's last-used child on this monitor;
2. falls back to the group's root/default desktop;
3. sends `_RWM_VIEW_DESKTOP` with the explicit monitor index.

Rebar keeps a per-monitor last-used child by stable desktop key while it is
running. Remembering the key rather than the numeric index preserves the
selection when a project is renumbered. RubyWM also publishes
`_RWM_DESKTOP_HISTORY` as one fixed-width MRU row per monitor, allowing
`rwmctl group` to make the same choice and preserving command-driven group
selection over RubyWM restarts.

## 5. Top project strip: a separate X11 dock

Each Rebar process creates a second window for its monitor. It is an ordinary
`_NET_WM_WINDOW_TYPE_DOCK` with `_NET_WM_STRUT_PARTIAL`, using only that
monitor's horizontal range.

Behavior:

- In `auto` mode, it appears whenever the bottom context label alone would omit
  the active project/view's useful name. `Coding` plus one `RubyWM` child must
  therefore show a `RubyWM` top tab; one child is not a reason to hide it.
- It contains only the children of the active high-level group.
- It disappears only for a true singleton whose bottom button already
  identifies the selected view, unless an `always` configuration is selected.
- Before unmapping, it clears its strut so RubyWM recomputes the work area.
- When mapping, it publishes the strut before the tiled layout is updated.
- Its contents change independently on each monitor using
  `_RWM_VISIBLE_DESKTOPS`.

The strip's height must be derived from the chosen font metrics:

```text
height = ceil(ascender - descender) + top padding + bottom padding
```

It must not be forced into the existing 40 pixels, and the font must not be
shrunk merely to hit an arbitrary bar height. A prototype should report the
actual calculated height; likely values can then be compared visually before
choosing a default.

Configuration modes:

```text
project_bar = auto    show when needed to identify the active project/view
project_bar = always  reserve it for every context
project_bar = off     keyboard/chooser only
```

The proposed default is `auto`, subject to testing whether work-area changes
when switching contexts are distracting.

## 6. Text and selection rendering

Both selectors use a clean, single-pass renderer:

- one antialiased text draw;
- no shadow or second offset draw;
- a solid bar background;
- high-contrast inactive text;
- an active background block or underline, not merely a red text copy;
- a distinct hover background;
- baseline positioned from Skrift font metrics rather than a magic `y + 2`.

No label is shortened merely to make every item simultaneously visible.

The top strip displays the child view's useful label:

```text
RubyWM    Compiler    wm/tools
```

It does not display:

```text
Coding/RubyWM    Coding/Compiler    Coding/wm/tools
```

If multiple views would have the same label, disambiguation is added at the
end, where it does not hide the useful prefix:

```text
RubyWM · main    RubyWM · tools
```

## 7. Overflow and navigation

Overflow is local to each level; the two levels never compete for the same
horizontal budget.

Bottom context bar:

- normally contains the bounded configured set;
- if it overflows, scroll controls move the viewport without changing the
  selected context;
- the active context is always brought into view.

Top project strip:

- keeps complete labels;
- uses a horizontal viewport with previous/next controls and mouse-wheel
  scrolling;
- scrolling the viewport does not switch desktops;
- clicking a project/view tab switches desktops;
- a trailing `+` appends and selects an empty tiled view in the current group;
- selecting via keyboard automatically scrolls the active tab into view.

This distinction is important: an overflow control navigates the list, while a
tab selects a desktop. The first patch incorrectly combined those actions.

## 8. Keyboard command surface

`sxhkd` remains the keyboard layer. Named/cycling operations use `rwmctl`,
while fixed numeric addresses fit directly in one ClientMessage:

```text
rwmctl group next
rwmctl group previous
rwmctl group view coding
rwmctl view next
rwmctl view previous
rwmctl view choose
```

Suggested bindings:

```text
Super+Tab              next high-level context
Super+Shift+Tab        previous high-level context
Super+]                next view in current context
Super+[                previous view in current context
Super+1..9             `_RWM_VIEW_GROUP 1..9`
Super+0                `_RWM_VIEW_GROUP 10`
```

Cycling order is the same order Rebar displays. These commands do not require
RubyWM to handle keyboard input or understand project manifests.

Numeric keybindings must not send `_NET_CURRENT_DESKTOP` directly. That
standard message intentionally addresses the flat X11 backing desktop and
would make a project such as Coding/Improve independently reachable by its
incidental backing index. `_RWM_VIEW_GROUP N` makes RubyWM resolve the
high-level context whose displayed address is `N`, then selects that group's
MRU project. An unused address remains meaningful even while Rebar hides its
empty placeholder: `_RWM_VIEW_GROUP 5` shows empty desktop 5. A child project's
incidental overflow index is never treated as a numeric group address.

## 9. X11 and RubyWM changes

The design stays compatible with ordinary X11 code:

- Every application window remains a root child.
- Every project view remains a normal EWMH desktop.
- Both bars are normal dock windows with standard struts.
- Other pagers may ignore the hierarchy and show the flat desktop list.
- On a non-RubyWM EWMH window manager, Rebar can fall back to one flat
  high-level button per desktop and omit the project strip.

RubyWM needs only small supporting changes:

- publish the group-root flag;
- distinguish explicitly configured desktops from implicit reusable slots;
- lease the first eligible placeholder for a new group, but append further
  projects in that group;
- repair legacy secondary leases by moving them to overflow and remapping
  their clients/history;
- preserve and release slot leases across restart/removal;
- publish aligned per-desktop client counts when occupancy changes;
- invalidate struts when a dock unmaps, not only when it changes properties or
  is destroyed;
- publish per-monitor desktop MRU history;
- continue publishing generation last.

Rebar must read a generation-checked snapshot and redraw only after
`_RWM_DESKTOP_GENERATION`, avoiding partial hierarchy updates.

## 10. Proposed Rebar structure

Keep the implementation divided into small pieces:

```text
lib/desktop_model.rb       pure grouping/order/current-selection model
lib/tab_strip.rb           one-level viewport, hit testing, clean renderer
lib/desktop_switcher.rb    bottom high-level selector
lib/project_bar.rb         top dock window and active-group child selector
lib/ewmh.rb                coherent state reads and semantic view messages
rebar.rb                   construction and event routing only
```

`TabStrip` is used by both levels but knows nothing about projects or EWMH. It
accepts items with keys and labels, a selected key, an available rectangle, and
a selection callback.

Do not expand the shared widget toolkit until the two Rebar strips demonstrate
a genuinely reusable missing primitive.

## 11. Staged implementation and gates

### Stage 0: restore

Status: completed by replacing the rejected presentation and renderer.

- Revert the unaccepted one-row group prefixes, truncation, and overflow
  behavior.
- Restore readable baseline rendering.

Gate: Rebar looks and behaves exactly as it did before the failed presentation
patch.

### Stage 1: model only

Status: completed with RubyWM, Rebar, and navigation unit coverage.

- Add `DesktopModel`, group-root metadata, label normalization, and explicit
  placeholder/lease state.
- Test legacy singleton desktops, explicit groups, synthetic migration groups,
  ordering, per-monitor current groups, root fallback, and omission of unused
  placeholders.
- Test the RubyWM allocation policy separately: reserved/visible/non-empty/
  leased slots are skipped, a new group's earliest eligible slot is leased in
  place, same-group children append, and new groups append only after address
  exhaustion.
- Add `rwmctl` group/view cycle resolution tests.

Gate: no UI changes; model examples produce the intended parent/child lists.

### Stage 2: clean single-level renderer

Status: completed. `TabStrip` renders text once and overflow controls do not
select a desktop.

- Add `TabStrip` with single-pass text, selection background, hit testing, and
  a non-selecting scrolling viewport.
- Test geometry using measured fake-font widths.
- Render the existing bottom high-level bar through it behind a feature flag.

Gate: screenshots at the user's real font and monitor scale are readable and
contain no shadowed/doubled text.

### Stage 3: top project-strip prototype

Status: completed and live-tested at 1280×800 under Xvfb.

- Create the second dock for one monitor.
- Compute its height from real font metrics.
- Implement auto map/unmap and strut changes.
- Populate it only from the active group's children.

Gate: interactive approval of size, placement, typography, and work-area
behavior before making it the default.

### Stage 4: multi-monitor and keyboard behavior

Status: implemented. RubyWM's two-monitor lease/routing test and semantic
group/view tests pass; a final two-Rebar visual check on the production monitor
geometry remains useful.

- Make each Rebar process follow its monitor's visible desktop.
- Add semantic group/view cycling to `rwmctl`.
- Verify group MRU and automatic viewport scrolling.

Gate: two monitors may show different groups and different project strips
without affecting one another.

### Stage 5: enable and remove legacy code

Status: completed. `auto` is the default and `PROJECT_BAR=off` is the escape
hatch.

- Enable the accepted layout by default.
- Remove the old flat switcher path only after a normal-use period.
- Keep `project_bar = off` as an escape hatch.

## 12. Test and acceptance matrix

Automated model tests:

- blank, whitespace, and numeric-default names display the number once;
- ten implicit empty slots do not produce ten high-level buttons;
- an explicitly configured unnamed singleton displays its number once;
- twelve Coding projects still produce one Coding high-level button;
- one Coding project on desktop 3 produces bottom `3: Coding` plus top
  `RubyWM`, not an information-losing `Coding`-only state;
- current flat desktop resolves to the correct group and child;
- group click resolves the last-used stable child key after renumbering, then
  the root fallback;
- creation/removal/rename updates both levels after one generation;
- scrolling never changes the selected desktop;
- clicking a tab sends the correct monitor and desktop index.

Xvfb integration:

- with desktop 1 visible and 2/10 explicitly configured, ensure leases desktop
  3, leaves the count at 10, and is reachable through the existing numeric
  binding;
- ensure a second Coding project appends at desktop 11, then verify `Super+3`
  returns to Coding's MRU project and `Super+5` still opens empty desktop 5;
- restart from a legacy snapshot with Coding projects on desktops 3 and 5;
  verify the latter and all of its windows migrate to desktop 11 while desktop
  5 becomes an available placeholder;
- skip a placeholder that is visible, has a client, or is already leased;
- restart RubyWM and retain the project at its leased index;
- remove that project and restore desktop 3 as an unnamed tiled placeholder
  without reindexing;
- exhaust reusable slots, then verify the next ensure appends desktop 11;
- create 20 Coding views; bottom button count remains bounded;
- project strip contains only Coding children;
- remove the active child and select the defined fallback;
- hide/show the top dock and verify `_NET_WORKAREA`;
- restart Rebar and rebuild from root metadata.

Xephyr multi-monitor integration:

- monitor 0 shows Coding/RubyWM while monitor 1 shows Art/Cover;
- each top strip has different contents and selection;
- clicking either strip changes only its own monitor.

Visual acceptance:

- test at the actual 3840-wide setup and at 1280 width;
- no doubled glyphs, shadows, clipped baselines, or unreadable scaling;
- full active context and project names are visible;
- current parent and child are unambiguous at a glance;
- overflow controls scroll without unexpectedly switching desktops.

## 13. Runtime presentation choices

The implementation currently uses:

1. `PROJECT_BAR=auto` by default; `always` and `off` are available.
2. A solid active background block.
3. The same configured font as Rebar, with the top window height derived from
   its real metrics plus padding.

The live 1280×800 integration check produced bottom
`2  3: Coding  10: System` and top `RubyWM`, with the bottom strut at 40 pixels
and the metric-derived top strut at 50 pixels.
