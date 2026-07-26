# Project screens: an Amiga-inspired workspace model for RubyWM and Rebar

Status: design, implementation plan, and staged implementation record,
2026-07-25.

The corrected RubyWM substrate is implemented in this tree: stable keys and
aligned metadata, lease-first ensure/view/release, standard EWMH count changes,
client reassignment/reindexing, restart restoration, semantic group/view
cycling in `rwmctl.rb`, and integration coverage. The sibling Rebar now
presents high-level contexts in its bottom dock and full project/view names in
a separate metric-sized top dock. The project-manifest launcher, launch
routing, `stage` layout, and individual window tabs remain later slices. See
[`rebar-two-level-selector.md`](rebar-two-level-selector.md).

## Recommendation in one paragraph

Keep one ordinary EWMH desktop for every visible project view. Make that flat
list dynamic, give each desktop a stable RubyWM key plus optional `group`,
`project`, and `mode` metadata, and let Rebar present the metadata as one or two
levels of tabs. Put project discovery, manifests, and process launching in a
small, short-lived `rwm-project` client; do not teach the WM about filesystems,
shells, Claude sessions, or project directories. Keep `sxhkd`. This retains the
simple X11 contract—standard properties out and ClientMessages in—while adding
only the mechanisms the WM must own: desktop lifecycle, window placement, and
per-monitor visibility.

Window-level tabs fit this design without turning project groups into fake
desktops. Represent a tab group as one leaf in the existing tiling tree, keep
all its X clients as ordinary root children, and draw a small WM-owned
override-redirect tab bar over that leaf. Only its active client is visible.
This avoids reparenting every client and keeps the first implementation
compatible with RubyWM's undecorated architecture.

The resulting model is:

```text
group/category        project             view = one EWMH desktop
────────────────      ───────────────     ──────────────────────────
Coding                rubywm              main       (tiled)
                                          tools      (floating)
                      Compiler            main       (tiled)
Art                   cover-2026          main       (stage)
                                          palettes   (floating)
System                workbench           desktop    (floating, pinned)
```

The flat desktop list remains intelligible to `wmctrl`, pagers, task switchers,
toolkits, and ordinary X clients. Grouping is an annotation that other software
can safely ignore.

## 1. What to preserve from Amiga screens

An Amiga screen was more than a numbered virtual desktop. It was a named working
context to which applications could deliberately attach windows. Workbench was
the special default public screen; other public or private screens could exist
at the same time, have job-specific characteristics, and be opened on demand.
AmigaOS later added user-defined automatic public screens that opened when a
program requested their name and closed with their last window.

Those are the useful semantics to carry over:

- A stable name rather than a permanent number.
- A Workbench-like default context with special desktop/backdrop behavior.
- Project contexts created when selected, not preallocated forever.
- A context may contain windows from several cooperating programs.
- A context can declare a default presentation: tiled, floating, or
  main-window-with-floating-tools.
- A project can have more than one related view.
- Selecting an existing context brings it forward without relaunching it.
- Selecting a context that does not yet exist can create it and run its setup.

The following Amiga properties should not become RubyWM goals:

- Per-screen colour depth, palette, refresh rate, or resolution. X11 virtual
  desktops share one root and one server display configuration.
- Physically dragging one screen down to expose another. Faithfully emulating
  that needs a compositor, snapshots, or nested X servers and is far outside
  RubyWM's scale.
- Requiring applications to understand a new public-screen API. Existing X
  applications should continue to publish ordinary ICCCM/EWMH properties.

In this document, **view** means the X11/EWMH desktop that RubyWM already calls
a `Desktop`. **Project screen** is the user-facing idea. **X screen** retains its
technical X11 meaning and is not used for virtual workspaces.

## 2. What the current code makes easy—and what is fixed today

### RubyWM

The present structure is already close to the required mechanism:

- [`Desktop`](../desktop.rb) is a small object with its own layout and child
  windows.
- Windows refer to a `Desktop` object, while `_NET_WM_DESKTOP` exposes the
  object's numeric EWMH index. This is helpful: adding a desktop is local;
  deletion mainly requires reindexing and republishing.
- [`Monitor#active_desktop`](../monitor.rb) is the single owner of the
  monitor-to-desktop association. A dynamic desktop can use the existing
  monitor swap behavior unchanged.
- Each desktop already chooses tiled or floating in
  [`WindowManager#process_config`](../wm.rb), and dialog/utility types already
  float independently of that choice.
- Tiled layouts already contain `WM_CLASS` receptacles, which are the beginning
  of a useful placement-rule mechanism.
- Desktop windows are already confined to a configured desktop and the WM
  publishes `_RWM_DESKTOP_WINDOW_DESKTOP` for Dwin.
- Commands already arrive as X11 ClientMessages; state is already published as
  standard or `_RWM_*` root properties.

The fixed behavior is concentrated in a few places:

- `process_config` allocates exactly `desktops.number` objects once.
- `_NET_NUMBER_OF_DESKTOPS`, `_NET_DESKTOP_NAMES`, and `_NET_WORKAREA` are
  published from that fixed array.
- Desktop identity is the array index. There is no stable semantic key.
- `move_to_desktop` falls back to index zero for an invalid index.
- There is no add/remove/rename command owned by the WM.
- The root event mask does not currently make external property mutation a
  general configuration channel.
- The only placement match is a layout receptacle's exact `WM_CLASS`; there is
  no transient launch-to-view rule.
- A lone tiled window is intentionally narrowed by `Node::LONE_WINDOW_MARGIN`,
  so "a tiled desktop with zero gap" is not quite the requested Gimp-style
  full-size background layout.

This means dynamic creation is modest work. Safe deletion, stable identity,
restart preservation, and asynchronous launch placement are the parts that need
deliberate design.

### Rebar

Rebar is also conceptually in the right layer: it reads EWMH properties and
sends EWMH ClientMessages. Its limitations are currently mechanical:

- [`DesktopSwitcher`](../../Rebar/lib/desktop_switcher.rb) reads
  `_NET_NUMBER_OF_DESKTOPS` only in `initialize`.
- It rebuilds on `_NET_DESKTOP_NAMES`, but not when the number changes.
- Every desktop button is packed left with no width budget, clipping policy, or
  overflow control.
- It reads the generated
  `_NET_CURRENT_DESKTOP_MONITOR_<n>` property for per-monitor highlighting.
- It sends a ClientMessage with that generated atom on click, but RubyWM has no
  corresponding `on_net_current_desktop_monitor_<n>` handler. The fallback to
  standard `_NET_CURRENT_DESKTOP` generally works because the click places the
  pointer on that monitor, but the custom command itself is currently inert.
- The current widget toolkit has only `PackedLeft` and `PackedRight`. It does
  not need a full scrolling widget to solve this: Rebar can measure labels and
  instantiate only the subset that fits.

The in-progress `rwidgets` work can express a Rebar-like bar and supports
clipping, but its own roadmap says the live Rebar port is still pending. Dynamic
project screens should not make that port a prerequisite.

## 3. Relevant prior art

The closest match is
[XMonad.DynamicProjects](https://xmonad.github.io/xmonad-docs/xmonad-contrib/XMonad-Actions-DynamicProjects.html).
It treats a workspace as a project with a name, directory, and optional start
hook; its prompt creates workspaces on demand, and its hook runs when the
workspace is empty. RubyWM should borrow the project/directory/start-action
split while improving two points for this use case: stable state across WM
restarts and an explicit distinction between "open" and "ensure missing
windows."

[XMonad.TopicSpace](https://xmonad.github.io/xmonad-docs/xmonad-contrib-0.17.0/XMonad-Actions-TopicSpace.html)
adds topic directories, empty-workspace actions, and recent-topic navigation.
[DynamicWorkspaceGroups](https://xmonad.github.io/xmonad-docs/xmonad-contrib/XMonad-Actions-DynamicWorkspaceGroups.html)
shows that groups can remain metadata over ordinary workspaces, including
multi-head sets, instead of becoming a second hiding mechanism.

For individual window tabs, the most relevant prior art is
[i3's tabbed container layout](https://i3wm.org/docs/4.14/userguide.html#_manipulating_layout)
and
[XMonad sublayouts](https://xmonad.github.io/xmonad-docs/xmonad-contrib-0.16.999/XMonad-Layout-SubLayouts.html):
the outer layout assigns one rectangle to a group and an inner tabbed layout
chooses the visible member. XMonad's
[tabbed decoration](https://xmonad.github.io/xmonad-docs/xmonad-contrib/XMonad-Layout-Tabbed.html)
also demonstrates that clickable title windows can be an independent layout
decoration. Suckless
[`tabbed`](https://tools.suckless.org/tabbed/) is admirably small, but is a
container for XEmbed-aware applications; it does not solve arbitrary grouping
of already managed top-level clients.

Other useful precedents:

- [i3](https://i3wm.org/docs/4.14/userguide.html) creates a workspace when the
  user switches to a name that does not exist. It also illustrates that
  ordinary named workspaces and per-window floating cover most Gimp-like cases.
- [herbstluftwm](https://herbstluftwm.org/herbstluftwm.html) supports dynamic
  add/remove/rename of named tags, relative navigation, per-tag floating mode,
  and one visible tag per monitor.
- [bspwm](https://github.com/baskerville/bspwm/blob/master/doc/bspwm.1.asciidoc)
  is useful for its named selectors, add/remove/rename operations, one-shot
  placement rules, receptacles, per-desktop tiled/monocle layouts, and explicit
  window stacking layers. RubyWM should borrow these small mechanisms, not
  bspwm's larger socket/query language.
- [Awesome's tag API](https://awesomewm.org/doc/api/classes/tag.html) shows
  dynamic tags with per-tag layouts. Awesome can also show multiple tags and
  attach a client to several tags; that extra generality is not needed here.
- KDE Activities demonstrate a full high-level layer over virtual desktops, but
  also demonstrate how quickly the idea grows into desktop widgets, history,
  privacy, and application integration. RubyWM only needs grouping and launch
  policy.

The standard foundation is already sufficient for a dynamic flat list. The
[EWMH specification](https://specifications.freedesktop.org/wm/latest-single/)
allows a pager to request a new `_NET_NUMBER_OF_DESKTOPS`, allows the WM or pager
to change `_NET_DESKTOP_NAMES`, and defines how clients must be moved when the
count shrinks. It has only one global `_NET_CURRENT_DESKTOP`, so independent
per-monitor visibility necessarily remains a documented RubyWM extension.

For launch attribution, the
[freedesktop startup-notification protocol](https://specifications.freedesktop.org/startup-notification/0.1/)
already defines `DESKTOP_STARTUP_ID` from launcher to process and
`_NET_STARTUP_ID` on the resulting window. That is a better first choice than
guessing solely from PIDs. `WM_CLASS` and `WM_WINDOW_ROLE` remain necessary
fallbacks because not every X client implements startup notification.

The Amiga comparison is grounded in the
[AmigaOS public-screen documentation](https://wiki.amigaos.net/wiki/Public_Screen_Type)
and its description of
[automatic named screens](https://wiki.amigaos.net/wiki/Screen_Programming).
The important precedent is named, demand-created work contexts—not the old
hardware display modes.

## 4. The recommended data model

Every view is a normal EWMH desktop. Three optional labels create the apparent
hierarchy:

| Field | Meaning | Example |
|---|---|---|
| `key` | Stable identity of this exact view | `rubywm:main` |
| `project` | Views that belong to one project | `rubywm` |
| `group` | High-level category used by the bar/keybindings | `coding` |
| `name` | Human-readable EWMH label | `RubyWM` |
| `mode` | Default layout/presentation | `tiled`, `floating`, `stage` |

This deliberately supports both interpretations of "dual layer":

- `Coding` can be the high-level desktop and each project a subordinate tab.
- A project can also own both `rubywm:main` and `rubywm:tools`, with the latter
  floating or displayed on another monitor.

The hierarchy is presentation and navigation metadata. Visibility is controlled
only by the underlying EWMH desktop. There is no hidden "tag within desktop"
state for other X tools to misunderstand.

### Stable keys versus EWMH indices

EWMH requires contiguous zero-based desktop indices. Removing desktop 3 shifts
later indices and requires updating `_NET_WM_DESKTOP` on their windows. Project
files and keybindings must therefore never store an EWMH index. They store
`rubywm:main`; clients resolve that key against the current metadata array each
time.

Workbench becomes a pinned key, not merely "desktop 10":

```yaml
desktops:
  number: 10                 # initial compatibility set, not a maximum

  10:
    key: workbench
    name: Workbench
    layout: floating
    desktop: true
    pinned: true
```

The existing numeric schema remains useful as an initial fixed set of
keyboard-addressable high-level addresses:

- a numbered entry present in configuration is reserved/static;
- a slot created only to reach `desktops.number` is an implicit reusable
  placeholder;
- the first project in a new group leases the first implicit slot that is not
  visible and has no managed windows;
- further projects in that group append as overflow EWMH desktops and do not
  consume another numeric address;
- only after those slots are exhausted does the EWMH count grow.

Thus a new project can replace unused desktop 3 in place and remain reachable
through `Super+3`, while configured desktop 2 (Todo) and desktop 10
(Workbench) are never candidates. If Coding owns address 3, its Improve child
may have backing index 11; `Super+3` still selects Coding's MRU child and
`Super+5` still selects empty desktop 5. `Super+0` should additionally resolve
`workbench` semantically so it remains stable if the initial pool is later
reduced.

### Standard properties

RubyWM should continue publishing and honoring:

- `_NET_NUMBER_OF_DESKTOPS`
- `_NET_DESKTOP_NAMES`
- `_NET_CURRENT_DESKTOP`
- `_NET_WM_DESKTOP`
- `_NET_WORKAREA`

When it starts honoring dynamic count requests it should also publish
`_NET_DESKTOP_GEOMETRY` and a `(0,0)` `_NET_DESKTOP_VIEWPORT` pair per desktop,
as required for a non-scrolling desktop model when the count changes.

### Small custom metadata surface

Parallel root arrays keep inspection simple and allow Rebar to remain a passive
client:

```text
_RWM_DESKTOP_KEYS       UTF8_STRING[]  stable per-view keys
_RWM_DESKTOP_PROJECTS   UTF8_STRING[]  project keys, empty if none
_RWM_DESKTOP_GROUPS     UTF8_STRING[]  group keys, empty if none
_RWM_DESKTOP_MODES      CARDINAL[]     0=tiled, 1=floating; 2=stage is reserved
_RWM_DESKTOP_FLAGS      CARDINAL[]     bits described below
_RWM_DESKTOP_CLIENT_COUNTS CARDINAL[]  managed-window count per desktop
_RWM_VISIBLE_DESKTOPS   CARDINAL[]     desktop index per monitor
_RWM_DESKTOP_HISTORY    CARDINAL[]     fixed-width MRU row per monitor
_RWM_DESKTOP_GENERATION CARDINAL        written last after a coherent update
```

String arrays use the same NUL-separated UTF-8 representation as
`_NET_DESKTOP_NAMES`. Arrays are aligned to `_NET_NUMBER_OF_DESKTOPS`; readers
must tolerate a short/missing custom array by padding defaults. The generation
property is written last so Rebar can avoid rendering a half-updated set after
several `PropertyNotify` events.

Flag meanings are:

```text
bit 0  explicitly configured/static
bit 1  pinned
bit 2  desktop-window host
bit 3  group root/default view
bit 4  originated as a reusable numeric slot
bit 5  reusable slot is currently an available placeholder
```

Bit 4 remains set while a project leases the slot; bit 5 is cleared for the
duration of the lease. This makes restart and removal semantics explicit
without guessing from a numeric name.

`_RWM_VISIBLE_DESKTOPS` replaces the family of generated
`_NET_CURRENT_DESKTOP_MONITOR_<n>` atoms as the preferred state API. The old
properties can be maintained during migration. `_NET_CURRENT_DESKTOP` remains
the desktop selected on the last active/commanded monitor for standard tools.

### Commands

Use standard messages wherever they fit:

- `_NET_CURRENT_DESKTOP` for the standard "view on active monitor" action.
- `_NET_WM_DESKTOP` to move a window.
- `_NET_NUMBER_OF_DESKTOPS` to honor generic pager count changes.

Add six semantic RubyWM actions:

```text
_RWM_VIEW_DESKTOP      data: desktop index, monitor index/current sentinel
_RWM_VIEW_GROUP        data: one-based group address, monitor+1/active zero
_RWM_SEND_TO_GROUP     data: one-based group address, monitor+1/active zero
_RWM_ADD_GROUP_VIEW    data: monitor+1/active zero
_RWM_REMOVE_DESKTOP    data: desktop index, flags, fallback index/sentinel
_RWM_ENSURE_DESKTOP    window: request-window XID; data: protocol version
_RWM_MOVE_DESKTOP      window: request-window XID; data: protocol version,
                       source index, target index/first-available sentinel
```

`_RWM_ENSURE_DESKTOP` needs strings and therefore cannot fit into five
ClientMessage words. The requesting client creates a tiny temporary X window,
writes one `_RWM_DESKTOP_SPEC` UTF-8 JSON property on it, and uses its XID as
the ClientMessage window field. RubyWM reads and validates the descriptor,
finds-or-creates by stable key, and writes a small `_RWM_DESKTOP_REPLY`
containing the resulting index and generation. The short-lived client polls
that property before destroying its request window. This is race-free between
multiple clients, stays entirely inside X11, and avoids making DRb or D-Bus
load-bearing.

This is not intended to become general RPC. Queries continue to read root/window
properties. If the request-window pattern starts accumulating unrelated verbs,
that is the point to reconsider a compact structured IPC service.

## 5. The project client

`rwm-project` should be a short-lived command, not a daemon and not part of
Rebar. It owns the policies RubyWM should not know:

- Resolve a path to a project and load its manifest.
- Derive a default stable key and display name.
- Find an existing view through `_RWM_DESKTOP_KEYS`.
- Ask RubyWM to ensure and show views.
- Launch configured processes only on creation, or explicitly on `ensure`.
- Maintain a small recent-project list for a chooser.
- Register temporary placement expectations before spawning.

The basic flow is:

```text
sxhkd / chooser / shell
          │
          ▼
  rwm-project open PATH ─── read PATH/.rwm.yml
          │
          ├── key exists ───────────────► _RWM_VIEW_DESKTOP
          │
          └── key absent
                │
                ├──► _RWM_ENSURE_DESKTOP ─► RubyWM publishes EWMH + _RWM state
                ├──► register launch placement
                └──► Process.spawn(..., chdir: project)
                                      │
                                      ▼
                              MapRequest / adopt
                                      │
                                      ▼
                    _NET_STARTUP_ID or matcher routes window

  Rebar watches root properties and redraws independently.
```

### Open, ensure, and restart are different operations

Use the desktop key, not a process name, as the definition of "project is
open":

- `open PATH`: if its primary view exists, switch to it and launch nothing. If
  it does not exist, create its views and run their start commands once.
- `ensure PATH`: switch to it, inspect configured window matchers, and launch
  only missing roles. This is explicit because singleton applications and
  daemonized clients make "missing" imperfect.
- `restart PATH` or `run PATH ROLE`: deliberately rerun configured commands.
- `close PATH`: remove only empty views by default. A forced close must name a
  fallback for remaining windows.

This is safer than automatically rerunning whenever a desktop happens to be
empty. A terminal may be restarting, an application may be between windows, or
the user may intentionally want an empty project. An optional
`start_when: empty` can reproduce XMonad DynamicProjects behavior for selected
projects.

### Suggested manifest

Keep the first schema small and declarative:

```yaml
version: 1

project:
  key: rubywm                   # default: stable key derived from realpath
  name: RubyWM                  # default: directory basename
  group: coding                 # optional

views:
  - key: main
    name: RubyWM
    mode: tiled                 # default
    monitor: current
    start:
      - argv: [my-terminal, --working-directory, "${project}"]
        match:
          class: ProjectTerminal

      - argv: [my-terminal, --working-directory, "${project}",
               claude, --resume, "${state.claude_session}"]
        match:
          class: ProjectClaude

  - key: tools
    name: RubyWM tools
    mode: floating
    monitor: next               # show simultaneously if another monitor exists
    start: []
```

`${project}` and `${state.*}` are argument-level substitutions, not shell
expansion. Commands should default to argv arrays and use
`Process.spawn(env, *argv, chdir:)`. If a shell command escape hatch is later
needed, it should be explicit (`shell: ...`) so quoting and trust are visible.
Use `YAML.safe_load` with a narrow set of permitted scalar/collection types.

The WM does not interpret the project path or command. Application-specific
restore remains application-specific: a Claude resume identifier, editor
session file, browser profile, or terminal server name is simply an argument in
the manifest or a small ignored local state file. RubyWM should not become a
session manager for those programs.

### Project discovery

The essential operation is `rwm-project open .`; it requires no index or scan.
A menu can begin with:

1. pinned paths from a small user config;
2. recently opened paths from `$XDG_STATE_HOME/rwm/projects.json`;
3. optional cached discovery roots.

Do not recursively scan the whole projects tree on every keypress. The chooser
frontend should be replaceable (`hmenu`, `dmenu`, `rofi`, or a simple terminal
selector) and kept outside RubyWM.

## 6. Reliable placement of newly launched windows

Launching while the target desktop is active is a useful fallback but is not
sufficient. Applications map asynchronously; a user can switch away, and a
multi-view project may start several commands at once.

Use this order:

1. Before `spawn`, generate a unique startup token and register
   token → target view/mode with RubyWM.
2. Set `DESKTOP_STARTUP_ID` in the child environment.
3. On adoption, prefer an exact `_NET_STARTUP_ID` from the window or its client
   leader.
4. Fall back to manifest matches over `WM_CLASS` instance/class and
   `WM_WINDOW_ROLE`; use title matching only as a last resort.
5. Fall back to the active monitor's desktop, which preserves today's behavior.

Temporary expectations should be one-shot or bounded by a count/idle timeout.
The manifest can state that an application creates several windows. PID and
process ancestry can be a later Linux-specific fallback, but should not be the
primary identity: terminal servers, browser singletons, D-Bus activation, and
forking applications routinely break it.

Do not automatically steal an already-running singleton application's window
from another project. A manifest may opt into `adopt: true`, but the default is
to launch and accept whatever the application does or report that its expected
window did not appear.

The current exact-class receptacles should remain. Dynamic launch rules and
persistent layout receptacles solve different problems:

- startup token/rule: which project view receives this newly launched window;
- receptacle: where inside that view a matching window belongs.

## 7. Layout modes

### `tiled`

This stays the default. Most project views should need no manifest layout
section at all.

### `floating`

This is today's `layout: floating`. It is appropriate for a Workbench, a Gimp
multi-window view, small utility collections, or a project's secondary tools
view. Dialog/utility/splash hints continue to float on tiled views.

### `stage`

This is the requested "main window fills the screen behind, tools float above"
mode. It should be a small dedicated layout rather than an EWMH fullscreen
hack:

- One primary matcher owns the stage rectangle.
- `cover: workarea` fills inside Rebar's strut; `cover: monitor` fills the
  monitor but still remains below docks.
- All non-primary windows float unless a rule says otherwise.
- The primary is kept in a background/normal layer below the floating tools.
- The desktop backdrop, if one exists, remains below the primary.

Do not set `_NET_WM_STATE_FULLSCREEN` on the primary. Fullscreen conventionally
raises a window over ordinary siblings and docks; that is the opposite of
"background canvas with tool windows." Adding honest support for the standard
`_NET_WM_STATE_BELOW`/`ABOVE` states and a deterministic local stacking order
would make `stage` interoperate better with clients.

A `StageLayout` can be smaller and clearer than teaching the binary tiler about
singleton margin exceptions, background layers, and floating-by-default
secondaries. Gimp's dialog/utility windows will already classify as floating;
the manifest only needs rules for any ordinary top-level tool windows.

`monocle`—several tiled windows all occupying the same rectangle—may be useful
later, but it is not required for the background-main use case.

## 8. Individual window tabs

Window tabs are a local layout feature, distinct from Rebar's project/view
tabs:

- A **view tab** selects a complete EWMH desktop and appears in Rebar.
- A **window tab** selects one X client inside one tile and appears immediately
  above that tile.

The distinction is important for other X11 software. Every member of a window
tab group has the same ordinary `_NET_WM_DESKTOP`; changing the selected member
does not pretend that another desktop became current.

### Recommended tree model: a tab group is a leaf

Add a `TabGroup` layout item alongside `Leaf`. A `Node` may therefore contain a
`Node`, `Leaf`, or `TabGroup`:

```text
Node :lr
├── Leaf(editor)
└── Node :tb
    ├── TabGroup(active: terminal)
    │   ├── terminal
    │   ├── claude
    │   └── test-runner
    └── Leaf(browser)
```

The outer binary tree assigns one rectangle to the `TabGroup`. The group splits
that rectangle into a small tab-bar rectangle and a content rectangle. Every
member remembers the content geometry, but only the active member is on-screen.

This is a better fit than making `tabbed` a whole-desktop layout:

- Several independently tiled tab groups can coexist.
- A normal leaf can be converted to a group without rebuilding the desktop.
- The existing split ratios and directional geometry remain useful.
- A project manifest can put terminal/Claude/test windows in one tab group while
  leaving an editor or browser in separate tiles.

It does require making layout-node operations less dependent on raw
`Leaf#window` assignment. Today swapping writes `l1.window = ...` and
`l2.window = ...`. Introduce layout-level operations such as `swap_items`,
`remove_window`, `group_windows`, and `detach_window`; let each item expose:

```text
windows             all client windows owned by the item
active_window       client used for focus/directional navigation
find(window)        the containing item
layout(geometry)    place visible content and decoration
keep(live_windows)  prune destroyed/unmapped members
```

That small interface makes tab groups possible without infecting every caller
with `Leaf`/`TabGroup` conditionals.

### Visibility needs reasons, not one boolean

The current `Window#hidden` boolean conflates "desktop is not visible" with the
physical off-screen implementation. Tabs introduce another independent reason:
an inactive tab can be hidden while its desktop is visible.

Refactor it to a set of blockers:

```text
visibility_blocks = { :desktop, :tab, :minimized, ... }
visible?          = mapped && visibility_blocks.empty?
```

`hide(:tab)` only performs the physical transition when the first blocker is
added; `show(:desktop)` does not reveal a window that still has `:tab`.
`resize_to_geom` continues updating the real content rectangle while a client
is off-screen, so selecting it later reveals it at the group's current size.
This also removes the risk of applying `HIDDEN_OFFSET` twice.

For compatibility, inactive tab clients should remain managed and retain their
`_NET_WM_DESKTOP`, but be placed in `IconicState` and have the WM-owned
`_NET_WM_STATE_HIDDEN` flag set. EWMH defines that flag for windows that would
not be visible even if their desktop were active, which describes an inactive
tab. A `_NET_ACTIVE_WINDOW` request for such a member should activate its tab,
show its desktop if necessary, and focus it.

`Window#publish_wm_state` currently reconstructs the property only from
fullscreen/maximize booleans. Before tabs, refactor this into a state set so
adding/removing `HIDDEN`, `BELOW`, or attention flags cannot accidentally erase
another valid state.

### Draw tab bars without reparenting clients

The minimum compatible tab bar is one small InputOutput window per visible
`TabGroup`:

- It is a child of the root, not a frame around the clients.
- It is `override_redirect`, recorded in RubyWM's internal-window set, omitted
  from `_NET_CLIENT_LIST`, and never adopted as a client.
- It is positioned at the top of the group's tile; the active client is resized
  into the remaining content rectangle.
- It is stacked immediately above the active client but below unrelated
  floating windows and docks.
- It receives `Expose`, `ButtonPress`, and optionally wheel events through the
  same X connection/event loop as the WM.
- Left click activates a tab; wheel or buttons cycle. Closing on middle click
  should be optional rather than a surprising default.

Titles come from `_NET_WM_NAME`, then `WM_NAME`, then `WM_CLASS`. RubyWM already
selects `PropertyChangeMask` on managed clients, so title changes can invalidate
only the containing bar. A fixed X core font is enough for a first version:
`pure-x11` already exposes `OpenFont`, `ImageText8/16`, GC fills, and ordinary
windows. Reusing Skrift or completing the `rwidgets` integration can improve
Unicode/metrics later, but should not be a prerequisite for proving tabs.

The bar can use equal-width cells initially, elide long labels, and disappear
when a group has only one member. That keeps the drawing module small.

### Why not reparent first

A frame window containing both tab bar and client children makes floating tab
groups elegant: move one frame, clip children naturally, and stack inactive
children inside it. It also changes many assumptions at once:

- client/root coordinate translation and synthetic `ConfigureNotify`;
- `WM_NORMAL_HINTS` gravity and frame extents;
- save sets and recovery when the WM crashes;
- transient/dialog parenting;
- fullscreen and client-requested restacking;
- shape/input extensions and compositor behavior;
- adopting existing windows across a WM restart.

RubyWM's current root-child/off-screen model can support tiled tab groups with
far less code. Reparenting should be reconsidered only if floating tab groups,
draggable decorations, or client clipping become important enough to justify a
general frame abstraction. It should not be introduced solely to draw a
20-pixel bar.

### Focus, navigation, and lifecycle

Directional focus treats a `TabGroup` as one spatial item and enters through its
active member. Separate commands operate within the group:

```text
_RWM_TAB_CYCLE    previous/next
_RWM_TAB_MERGE    direction or target window
_RWM_TAB_DETACH   direction for the new adjacent tile
_RWM_TAB_SELECT   member window ID or index
```

A compact keyboard workflow is:

- focus window A;
- merge the nearest window in a direction into A's tile;
- cycle members with a dedicated previous/next binding;
- detach the active member beside the group when it needs its own tile.

A future mark-and-merge command can handle non-adjacent windows. Dragging tabs
is not needed in the first version.

When the active member closes or unmaps, activate the next member, preferably in
group MRU order. Collapse a one-member group back to a `Leaf` and destroy its bar.
If the desktop hides, unmap the internal bar and add only the `:desktop` blocker
to all members; the inactive members retain `:tab`.

Dialogs require one deliberate rule. Read `WM_TRANSIENT_FOR`; mapping a transient
for an inactive member activates that member before showing the dialog. When the
user changes tabs, hide non-modal transients belonging to the old member along
with it. Modal transients should either keep their parent tab active or block the
tab change until dismissed. Never put dialogs, docks, desktop windows, or
override-redirect popups into a `TabGroup`.

Fullscreen applies to the active member: temporarily hide the local tab bar,
cover the monitor, and restore the group geometry/bar on exit. A tab-hidden
fullscreen member must not remain fullscreen above the selected tab. The
smallest predictable rule is that selecting another member exits fullscreen
before changing the active tab.

### Persistence and X11 properties

Set small custom properties on each member so a RubyWM restart can reconstruct
groups while the X clients survive:

```text
_RWM_TAB_GROUP   CARDINAL   session-unique group ID
_RWM_TAB_INDEX   CARDINAL   order within the group
_RWM_TAB_ACTIVE  CARDINAL   1 on the selected member, 0 otherwise
```

The group ID must not be a leader window ID because the leader can close.
Allocate it from a root `_RWM_NEXT_TAB_GROUP` counter. On startup, group only
live regular windows that still share a desktop; repair or clear inconsistent
properties. Exact outer-tree positions need not survive the first
implementation—the same compromise already applies to ordinary tiled windows
on WM restart—but membership, order, and selected member can.

Project launch rules can optionally name a tab group:

```yaml
start:
  - argv: [my-terminal, --working-directory, "${project}"]
    role: shell
    tab_group: consoles

  - argv: [my-terminal, --working-directory, "${project}",
           claude, --resume, "${state.claude_session}"]
    role: claude
    tab_group: consoles
```

The startup token first routes each window to the correct project view; the
named tab-group rule then places both into one tiling item. This keeps project
screens and individual window tabs composable rather than competing models.

### Likely implementation size

The visual bar is not the expensive part; correct visibility and lifecycle are.
A rough Ruby-sized estimate, after tests clarify the interfaces, is:

| Work | Approximate new/changed code |
|---|---:|
| Leaf-item refactor plus `TabGroup` | 80–130 lines |
| Reasoned visibility and EWMH state | 40–80 lines |
| Minimal X core-font tab bar and events | 80–140 lines |
| Commands, title/transient/fullscreen integration | 60–120 lines |

So a credible complete first version is roughly 260–470 lines of production
change, plus tests. A keyboard-only proof without persistence, transients, or a
drawn bar could be about half that, but it would not yet be safe as a daily
layout. This is still compatible with the minimalist project; it is large
enough to deserve its own staged feature rather than being folded casually into
the dynamic-desktop patch.

### Scope of the first tab implementation

Support only regular tiled clients initially. Defer:

- grouped floating geometry and moving/resizing the group as a unit;
- tab dragging/reordering;
- icons, close buttons, urgency badges, and rich theming;
- nested tab groups;
- serializing the entire outer tiling tree.

The useful first slice is keyboard merge/detach/cycle, a clickable title strip,
correct hidden/focus state, cleanup on close, and project-manifest placement.

## 9. Multi-monitor behavior

Retain the existing global pool of desktops that can move freely between
monitors. Do not adopt i3/bspwm's "workspace belongs to output" ownership model.

The custom command should address the destination monitor explicitly:

- `current`: monitor under the pointer/focused window;
- `next`/`previous`: resolved by the client or WM against monitor order;
- numeric ID initially;
- named outputs only after RubyWM uses RandR names rather than Xinerama indices.

A manifest with `main: current` and `tools: next` can therefore open the tiled
project on the active monitor and its floating auxiliary view on another one.
On a one-monitor system the tools view still exists but is not simultaneously
visible.

Rebar instances read `_RWM_VISIBLE_DESKTOPS[monitor]` for highlight state and
send `_RWM_VIEW_DESKTOP` with their monitor ID. The existing
`_NET_CURRENT_DESKTOP_MONITOR_<n>` properties can remain read-only compatibility
state until Rebar and Dwin no longer need them.

## 10. Switching and the Rebar presentation

### Keep `sxhkd`

Dynamic workspaces do not require dynamic key grabs. Bind a fixed vocabulary to
semantic commands:

```text
Super+P                  project chooser/open
Super+Tab                previous view (global MRU)
Super+[ / Super+]        previous/next view in current group
Super+Alt+[ / +]         previous/next view in current project
Super+1..9               semantic group addresses 1..9
Super+0                  semantic group address 10
Super+Shift+P            move focused window to a chosen project view
```

Exact keys are a user-config decision; the important part is that the `sxhkd`
file uses `_RWM_VIEW_GROUP N` rather than raw EWMH indices. A child project's
backing desktop number must never become an independent numeric shortcut.
An otherwise hidden empty placeholder remains selectable by its number.
RubyWM remains an X11 ClientMessage consumer, not a keyboard daemon.

### Rebar's minimum useful update

The rejected flat dynamic row has been replaced while retaining its useful
protocol work:

- Watch `_NET_NUMBER_OF_DESKTOPS`, `_NET_DESKTOP_NAMES`,
  `_RWM_DESKTOP_GENERATION`, and `_RWM_VISIBLE_DESKTOPS`.
- Reread the count and all names/metadata on generation changes.
- Remove the fixed `length: 1000` assumption when reading name arrays.
- Normalize blank/numeric default labels so `"1"` displays as `1`, never
  `1: 1`.
- Omit unused implicit placeholders, except for a placeholder that is currently
  visible and therefore must remain identifiable.
- Make wheel/click navigation use the same monitor-aware semantic view command.

The implemented presentation is specified in
[`rebar-two-level-selector.md`](rebar-two-level-selector.md). It contains no
group/name prefixes, truncation, shadowed text, or one-row project overflow.

### Optional Amiga-like two-level strip

The original two-row sketch was:

```text
  Workbench   Coding   Art   System                 [status]
              Compiler   RubyWM/main   RubyWM/tools
```

The 40-pixel Rebar cannot render those two rows readably at the current font
size. The corrected design keeps high-level contexts in the existing bottom
bar and uses a separate, font-metric-sized top dock for projects/views on each
monitor. Group names are not repeated in child labels, and labels are not
truncated merely to fit every open view at once.

Do not show every open view all the time. Overflow is best solved by
group-relative context plus a chooser/MRU binding, not by squeezing 30 labels
into 3840 pixels.

## 11. Lifecycle, persistence, and cleanup

### WM restart

Root-window properties survive a WM process restart within the same X session.
Before RubyWM overwrites them at startup it should snapshot a coherent prior
`_NET_NUMBER_OF_DESKTOPS`, names, and `_RWM_*` metadata, validate them, and merge
them with pinned config entries. Existing windows' `_NET_WM_DESKTOP` values then
repopulate those desktop objects as the WM adopts the root tree.

The binary tiling tree need not be serialized initially. Windows can be tiled
again on adoption, as they are today. Stable project/view identity matters more
than exact split restoration.

If no coherent RubyWM metadata exists, `config.yml` is authoritative. Never
trust an old count alone: stale properties from another WM must not create a
large anonymous set without RubyWM's keys/generation marker.

### X-session restart

Project manifests are durable definitions; open desktop instances are session
state. After a new X session, selecting a project creates it and runs its start
commands. Optional pinned/autostart projects can be opened by `.xinitrc`, but
restoring every previously open project should be an explicit later feature.

### Removal

The safest defaults are:

- Pinned/static/Workbench views cannot be removed through the ordinary command.
- Removing a project that leased an initial slot restores that slot in place
  as an unnamed, tiled, available placeholder. It does not decrement the count
  or change later indices.
- Removing an appended dynamic view deletes it and reindexes later desktops.
- An empty dynamic view can be removed.
- A non-empty view requires `--force` plus an explicit fallback project/view.
- When deletion actually reindexes later desktops, every affected window's
  `_NET_WM_DESKTOP` is updated.
- Active monitor references, current desktop, work areas, names, metadata, and
  visible arrays are republished as one generation.

Do not auto-remove immediately when the last window closes. Empty views are
useful and application restarts create gaps. Optional garbage collection can
close empty dynamic views after a long grace period, but should default off.

## 12. Alternatives considered

| Option | Advantage | Main cost | Verdict |
|---|---|---|---|
| Fixed large pool (for example 32 desktops) plus a custom "active" list | Smallest WM patch; indices never shift | Lies to standard pagers, leaves fake empty desktops, retains a hidden cap | Reject as the general model |
| Reuse implicit slots in the existing configured initial count, then grow normally | Preserves current numeric bindings while capacity is available; no new hidden cap | Requires explicit lease/release state | **Use as allocation policy** |
| Flat dynamic EWMH desktops plus metadata | Standard tools see the truth; one visibility model; groups/views remain flexible | Requires safe reindexing and a small custom ensure request | **Recommended** |
| Fixed top-level EWMH desktops with private subdesktop tabs inside each | Numeric top level stays stable | Two hiding systems; ordinary X tools cannot identify the visible subdesktop; much more WM state | Reject |
| Put project manifests and spawning in RubyWM | One process controls everything | Filesystem, YAML, shell, app policy, and session state bloat the WM and its failure surface | Reject |
| Use DRb/D-Bus as the primary API | Structured requests and replies are easy | New load-bearing service/protocol; bypasses the existing X-first design | Keep as future escape hatch |
| One nested Xephyr/X server per project | Strong isolation; closest to a true separate display | Clipboard, drag/drop, GPU, input, DPI, and window movement become separate-session problems | Niche opt-in, not the workspace model |
| Compositor-driven draggable screen stack | Closest visual homage | Requires compositing and off-screen scene management far larger than the WM | Defer indefinitely |

Reusing the existing compatibility slots is not the rejected fixed-large-pool
model: all leased views remain real EWMH desktops, and the count still grows
normally when no suitable slot remains. The reusable pool is the set the user
already addresses with `Super+1..0`, not a second private active list.

## 13. File-level implementation outline

### RubyWM repository

[`desktop.rb`](../desktop.rb)

- Add `key`, `project`, `group`, `mode`, and flags.
- Distinguish explicit configured entries, available implicit slots, leased
  slots, and appended dynamic desktops.
- Keep `id` mutable only for controlled reindexing.

[`wm.rb`](../wm.rb)

- Split desktop construction from config iteration.
- Add `ensure_desktop`, `move_desktop`, `remove_desktop`,
  `reindex_desktops`, and a single `publish_desktop_state`.
- Make `ensure_desktop` lease the earliest eligible implicit slot for the first
  project in a group, append that group's further projects, and release a
  leased slot in place on removal.
- On startup, migrate legacy secondary same-group leases to overflow while
  remapping their windows, visible monitor, and MRU history.
- Honor `_NET_NUMBER_OF_DESKTOPS` requests.
- Publish standard geometry/viewport plus custom metadata/visible arrays.
- Add `_RWM_VIEW_DESKTOP`, `_RWM_VIEW_GROUP`, `_RWM_SEND_TO_GROUP`,
  `_RWM_ENSURE_DESKTOP`, `_RWM_MOVE_DESKTOP`, and `_RWM_REMOVE_DESKTOP`.
- Read a prior coherent RubyWM root snapshot before publishing startup state.
- Track a small desktop focus history.
- Add temporary startup-token and matcher placement rules.
- Dispatch events for internal tab-bar windows before ordinary client
  button/expose handling, and add the `_RWM_TAB_*` commands.
- Advertise the additional EWMH state hints only as their implementations land.

[`window.rb`](../window.rb)

- Cache/read `_NET_STARTUP_ID`, `WM_WINDOW_ROLE`, and client-leader fallback.
- Apply placement before final desktop assignment.
- Replace the single hidden boolean with reasoned visibility blockers.
- Maintain `_NET_WM_STATE` as a set and publish WM-owned `HIDDEN` state.
- Read `WM_TRANSIENT_FOR` so tab selection and dialogs stay coherent.
- Add honest `BELOW`/`ABOVE` state/layer behavior if `stage` lands.

[`leaf.rb`](../leaf.rb), [`node.rb`](../node.rb), and
[`tiled.rb`](../tiled.rb)

- Introduce a small leaf-item interface instead of mutating `Leaf#window`
  directly from focus/move commands.
- Add group/detach/swap operations at the layout level.
- Treat a tab group as one spatial item but all its members as managed children.

`tab_group.rb` (new)

- Own member order, active/MRU member, content geometry, visibility blockers,
  persistent member properties, and collapse-to-leaf behavior.

`tab_bar.rb` (new)

- Create/draw/position the root-level override-redirect title strip.
- Handle expose/click/wheel events and title invalidation with no widget-toolkit
  dependency in the first version.

`stage.rb` (new)

- Own one primary fill rectangle and route other windows through floating
  placement.
- Enforce a deterministic desktop-backdrop → primary → floating → dock stack.

[`config.yml`](../config.yml)

- Add stable keys/pinned flags while preserving the current schema.
- Treat `desktops.number` as an initial count, never as a maximum.

[`climsg.rb`](../climsg.rb)

- Keep as the primitive numeric/atom ClientMessage sender.
- Do not overload it with project manifest behavior.

New `rwm-project` client (location to choose)

- Shared minimal X property/message helper.
- Safe manifest loader, key resolver, chooser adapter, start/ensure commands,
  and startup-token registration.
- No resident process.

### Rebar repository

[`lib/ewmh.rb`](../../Rebar/lib/ewmh.rb)

- Read complete dynamic arrays, `_RWM_DESKTOP_CLIENT_COUNTS`,
  `_RWM_VISIBLE_DESKTOPS`, and generation.
- Send `_RWM_VIEW_DESKTOP` for an explicit monitor.

[`lib/desktop_switcher.rb`](../../Rebar/lib/desktop_switcher.rb)

- Refresh count as well as names.
- Render only high-level contexts in the existing bottom bar.
- Hide available placeholders only while empty and inactive; retain an
  occupied unnamed desktop under its bare number.
- Remember each group's last-used project by stable key so renumbering does
  not lose the selection.

`lib/desktop_model.rb` and `lib/tab_strip.rb` (new)

- Build the pure group/project/view model, including normalized fallback
  labels.
- Provide one clean single-pass tab renderer and a non-selecting overflow
  viewport.

`lib/project_bar.rb` (new)

- Own the separate top dock for this monitor and show the active context's
  complete project/view labels.
- In automatic mode, remain visible even for one child when hiding it would
  reduce `Coding / RubyWM` to the information-poor label `Coding`.

[`rebar.rb`](../../Rebar/rebar.rb)

- Subscribe/redraw only for relevant root properties.
- Pass the available left-side width into the switcher.
- Construct and route events to the independently sized top project strip.

`names.txt`, `setname.rb`, and `setnames.rb`

- Retain temporarily as generic EWMH tools, but remove them from normal startup.
  Manifest/config labels and dynamic metadata become authoritative.

## 14. Staged delivery and tests

### Stage 0: semantic compatibility

- Give Workbench a stable key and bind `Super+0` through a semantic client.
- Add `_RWM_VISIBLE_DESKTOPS` while preserving the old per-monitor properties.
- Retain Rebar's coherent metadata refresh and monitor-aware view command while
  rolling back the rejected group-prefix, truncation, overflow, and shadowed
  rendering changes.

Implementation status: delivered. RubyWM metadata and monitor-aware commands
are live; Rebar's rejected presentation has been replaced. The exact `sxhkd`
bindings remain user configuration.

Exit test: the existing ten-desktop workflow behaves identically, including
dual-monitor swaps and Dwin confinement.

### Stage 1: dynamic flat desktops

- Implement ensure by leasing the first eligible implicit initial slot for a
  new group and appending same-group children; add rename, safe
  release/removal, standard dynamic count handling, and coherent property
  publication.
- Preserve dynamic metadata over a RubyWM restart in the same X session.
- Add a simple `rwmctl ensure/edit/current/view/remove` without project
  launching. `current --field pwd` is also the compatibility hook used by the
  existing terminal-directory helper.

Implementation status: delivered.
`rwmctl list/current/ensure/edit/view/group/move/remove/count`, coherent root
state, guarded metadata editing, active-project working-directory lookup, slot
lease/release, explicit atomic renumbering, forced fallback reassignment,
restart recovery, and integration coverage are present.

`edit current --key ... --group ...` can claim the visible implicit slot in
place, which makes an empty numeric address into a group without running the
allocator. `--rekey-group` changes that group key across all child views.
Rebar's top-strip `+` sends `_RWM_ADD_GROUP_VIEW`, appending and selecting a
temporary empty tiled child ready for the same edit command.

Exit tests:

- With desktop 1 visible and configured desktops 2 and 10 reserved, ensure a
  project; verify desktop 3 is leased, the count remains 10, and the project is
  reachable through the existing `Super+3` binding.
- Verify visible, non-empty, configured, pinned, desktop-host, and already
  leased slots are skipped deterministically.
- Remove the leased project; verify desktop 3 is restored in place as an
  unnamed tiled placeholder and no later index changes.
- Restart RubyWM during a lease; verify its stable key, index, and windows
  survive, then release correctly.
- Create a second project in the same group; verify it appends, the group's
  numeric address selects its MRU child, and another empty numeric address is
  still reachable.
- Restart from an old duplicate-lease snapshot; verify secondary same-group
  projects and their windows move to overflow while their numeric slots are
  restored.
- Exhaust the eligible pool, then add desktop 11; verify count, name, workarea,
  viewport, key, and Rebar's two-level model.
- Free an initial slot and explicitly move desktop 11 into it; verify its
  windows, layout, monitor ownership, and metadata move with it.
- Move a window to it with standard `_NET_WM_DESKTOP`.
- Remove an empty middle desktop; verify later windows' indices.
- Shrink through standard `_NET_NUMBER_OF_DESKTOPS`; verify EWMH fallback rules.
- Restart RubyWM; verify keys/names and window assignments survive.
- Repeat on two monitors; verify `_RWM_VISIBLE_DESKTOPS`.

### Stage 2: project manifests and launch-on-create

- Add `rwm-project open .`, recent paths, safe argv spawning, and the minimal
  manifest.
- First use active-view placement, then add exact `WM_CLASS` fallback rules.

Exit test: selecting an unopened project creates and names a tiled view and
opens a terminal in its directory; selecting it again launches nothing.

### Stage 3: reliable routing and multiple views

- Add startup-token routing, role/class matchers, group/project metadata, and
  `monitor: next`.
- Add global/group/project cycle commands and focus history.
- Add Rebar's separately gated bottom-context/top-project presentation from
  [`rebar-two-level-selector.md`](rebar-two-level-selector.md).

Exit tests:

- Switch away immediately after `open`; the delayed terminal still lands on the
  intended project.
- Open tiled and floating views concurrently on two monitors.
- An application without `_NET_STARTUP_ID` lands correctly by `WM_CLASS`.
- A singleton app is not silently stolen from another project.

### Stage 4: individual tiled window tabs

- Refactor visibility blockers and WM state publication.
- Add the leaf-item interface, `TabGroup`, keyboard merge/detach/cycle, and
  cleanup.
- Add a minimal clickable root-level tab bar.
- Persist group membership/order/active member on client properties.
- Allow project start entries to name a tab group.

Exit tests:

- Group two clients; only the active member is on-screen and both retain the
  same `_NET_WM_DESKTOP`.
- Desktop hide/show does not reveal the inactive member.
- Directional focus sees one spatial item; tab cycling changes input focus.
- `_NET_ACTIVE_WINDOW` on an inactive member selects its tab.
- Close active/non-active members and verify group selection/collapse.
- Change `_NET_WM_NAME` and verify only its bar redraws.
- Map a transient for an inactive member and verify its parent tab activates.
- Fullscreen the active member and verify the bar returns on exit.
- Restart RubyWM and reconstruct membership/order from window properties.

### Stage 5: `stage` mode

- Add the primary/background layout and stack layers.
- Test with a synthetic main window plus dialog/utility/ordinary floaters before
  trying Gimp.

Exit tests:

- Primary fills workarea or monitor as configured.
- Floaters remain above it and usable.
- Rebar/docks remain above it.
- A Workbench desktop window, if present, remains below it.

### Stage 6: optional polish

- Explicit `ensure` roles, optional empty-view start hooks, long-grace garbage
  collection, session-wide project restore, named RandR outputs, and floating
  tab groups.

None of these should block the useful vertical slice.

## 15. Proposed first vertical slice

The smallest slice that proves the idea without committing to the full UI is:

1. Add stable desktop keys and `ensure/view` through X11.
2. Lease unused implicit slots first, append only after exhaustion, and publish
   correct EWMH state.
3. Make Rebar refresh coherent metadata and feed the two-level model while
   hiding available placeholders.
4. Add `rwm-project open PATH` with one view and argv start commands.
5. Route by active view plus an explicit `WM_CLASS` matcher.
6. Bind a chooser, next/previous, and semantic Workbench in `sxhkd`.

Steps 1–3 and the generic `rwmctl` foundation are implemented and verified.
Steps 4–6 are the next cross-project slice.

That is already enough to replace "rename desktop manually, then remember which
number it was" with "open RubyWM" and to reopen a terminal/Claude command only
when RubyWM's project view is newly created. Groups, auxiliary floating views,
startup tokens, and `stage` then extend a working model rather than rescuing an
overdesigned first version.

Window tabs should be the next independent vertical slice: group two existing
tiled windows from the keyboard, cycle them correctly, then add the small
clickable bar. Manifest-driven `tab_group:` placement comes only after manual
groups are solid. This sequencing keeps tab-state bugs from being confused with
project-launch attribution bugs.

## 16. Decisions worth making only after the vertical slice

- Whether group tabs deserve a permanent second row or should appear only in the
  chooser.
- Whether window tab bars use a fixed core X font permanently or later share
  Skrift/`rwidgets` text rendering.
- Whether demand for floating tab groups justifies general reparented frames.
- Whether empty dynamic views should ever auto-close.
- Whether exact tiling trees need persistence.
- Whether a project-local state file should hold application session IDs or a
  global XDG state file should.
- Whether `stage` needs standard EWMH below/above controls exposed to clients.
- Whether the request-window protocol remains small enough to prefer over D-Bus.

The initial defaults should be conservative: one flat dynamic list, tiled
views, explicit close, no automatic process stealing, no shell strings, no
keyboard handling in the WM, and no compositor requirement.
