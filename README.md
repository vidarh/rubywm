
# A Ruby X11 Window Manager

**WARNING**:

This is experimental. It will eat your cat and burn down your house,
format your hard drive and post all your secrets to Facebook.

Also it *will* likely crash on you.

If you're not comfortable figuring out how to recover from an X session
where your window manager is gone and lots of your windows appears to have
disappeared ... somewhere, and you might not be able to get focus to a
terminal window without switching to the text console, this is not yet
for you.

## So why should I run this?

You almost certainly shouldn't.

## But what is it then, at least?

It's a minimalist (currently <1K lines) pure Ruby (including the X11
driver) X11 window manager. It is focused on tiling, but allows you to
choose to assign a tiling layout to specific desktops or leave them
floating. Currently *whether or not you use tiling or floating layout*
there is *no window decoration* and windows are not draggable or
resizable by pulling on borders (but you can do that with Windows
key + left/right mouse button)

Like bspwm, which was an inspiration, the wm supports *no* keyboard
handling - all keyboard handling is deferred to separate tools like
sxhkd. Unlike bspwm this WM has no dedicated IPC mechanism. Instead,
so far, all communication happens via X11 ClientMessage events, which
means any tool, like xdotool etc. that can produce those events can
control the WM.

It now has full support for multiple monitors using Xinerama. You can configure
monitors in config.yml with their resolution and position. Key features include:

- Each monitor displays a different desktop independently
- Desktop switching only affects the current active monitor
- If you switch to a desktop shown on another monitor, they swap
- Windows scale appropriately when moved between monitors of different resolutions
- New windows will be placed on the monitor containing the currently focused window
- Easy window movement between monitors

## Screenshots

Note that most of what you see here is not the wm. The wm decoration is minimalist: a 1 pixel rectangular frame. Nothing else. But people want to see screenshots anyway, so here:

<div>
<a href="https://github.com/vidarh/rubywm/blob/8eed458c1b9f9d25372df3932ab1237149bb90c0/screenshots/2024-01-11_19-45.png?raw=true"><img style="display: inline; width: 48%" src="https://github.com/vidarh/rubywm/blob/8eed458c1b9f9d25372df3932ab1237149bb90c0/screenshots/2024-01-11_19-45.png?raw=true"></a>
<a href="https://github.com/vidarh/rubywm/blob/master/screenshots/2024-01-11_20-04.png?raw=true"><img style="display: inline; width: 48%" src="https://github.com/vidarh/rubywm/blob/master/screenshots/2024-01-11_20-04.png?raw=true"></a>
</div>

## Why did you write this?

It started with mild frustration that bspwm handled my desire for one of
my virtual desktops to have floating windows by default poorly. It's
possible, but didn't work great for me. It also frustrated me that my
file manager was visible on all the virtual desktops instead of just the
floating one. I also happened to know an X11 WM can be *really*
minimal to start off with.

So I ditched bspwm, and translated TinyWM - a really minimal C wm - to
Ruby, made that my main wm, and gradually started adding the features
I needed, drawing a lot of inspiration from the code of KatriaWM to
figure out how to make my experience gradually less painful.

This has been my only WM since that day, and I now feel that *I* have
rough parity in term of the features *I* use with bspwm. That does
not mean it will have parity for you - it lacks lots of things. It
also does not mean there aren't plenty of bugs, because there are.

## Will you add...?

Maybe. As long as it can either 1) be done with little code, and/or
2) be done by you, and/or 3) it can easily be kept as a separate gem.

Talk to me. But please respect I'm primarily releasing this "as is", and
I'm not committing to supporting this - I *do not care* if you decide
it doesn't work for you and is horrible. I'll think it's great if you
get some utility out of this code, though. But my goal is not a big user
base. Or *a* user base.

My goal is a functional, minimalist WM that works *for me*. And so, I'll
help if it's not compromising my own goal. To the extent our goals are
not compatible, I'm happy to e.g. split out generic/reusable
functionality so people can fork this and we can still benefit from
sharing the bits where we do agree how things should be.


## Pre-requisites:

 * sxhkd or similar is needed to handle input, as this WM does
 *not* listen to keybindings other than grabbing windows+ left/right
 mouse button for move and resize.

* A recent version of Ruby. I currently use 3.2.2

## How to run

This is a subset of my .xinitrc.

WARNING: You probably want to try this in a vm or something first and
see if it works for you:

```sh
  (sxhkd 2>&1 | logger -t sxhkd) &
  (cd ~/Desktop/Projects/wm ; ruby rubywm.rb 2>&1 | logger -t rubywm) &
  
  while true do
    wait
    sleep 5
  done
```

### Command Line Options

RubyWM supports these command line options:

- `--drb`: Start with DRb service enabled for remote control
- `--debug`: Open an IRB session for debugging

For most "normal" window managers, people tend to start the window
manager last and let it end the X session when it quits, but since
this is in development, I'm not going to do that because most stuff on
my desktop can survive my WM crashing and being restarted just fine,
as it should be, but will obviously get killed if the X session dies.

## Dynamic project desktops

`desktops.number` is the initial desktop count, not a maximum. Every desktop
still has an ordinary contiguous EWMH index, while RubyWM also publishes a
stable string key that scripts can retain when indices change.

Numbers in that initial set are stable high-level addresses. The first project
in a group may lease the first eligible empty address; further projects in the
same group are appended as ordinary overflow EWMH desktops and appear only in
that group's project strip. They do not consume more numeric addresses. Thus,
if Coding owns address 3 and its last-used project has backing index 11,
`Super+3` enters that project while `Super+5` still opens empty desktop 5.

The bundled semantic client accepts stable keys. `~/bin/rwmctl` is a symlink
to it, so the shorter form works from any directory:

```sh
rwmctl list
rwmctl current --json
rwmctl current --field pwd

rwmctl ensure project:rubywm \
  --name RubyWM \
  --pwd "$HOME/Desktop/Projects/wm" \
  --group Coding \
  --mode tiled \
  --view

rwmctl edit project:rubywm \
  --name RubyWM \
  --pwd "$HOME/Desktop/Projects/wm" \
  --group Coding

rwmctl view workbench
rwmctl group 3
rwmctl group next
rwmctl view next
rwmctl move Coding --first
rwmctl move Novelator --to 4
rwmctl remove project:rubywm
```

`ensure` is idempotent: it reports whether it created the desktop, so a later
project launcher can launch a manifest only on first creation. Supplying a
name, project working directory (`--pwd`, with `--project` retained as an
alias), or group for an existing key refreshes that metadata without treating
it as newly created. `edit` accepts the same metadata options but refuses a
missing stable key, making it safer for interactive changes and scripts where
a typo must not create a new desktop. `--clear-pwd` and `--clear-group` remove
those values. Relative `--pwd` values are expanded when `rwmctl` runs, so
`rwmctl edit current --pwd .` stores the caller's absolute directory.

`current` reports the desktop on the monitor under the pointer. `--json`
returns all of its settings; `--field key|name|pwd|group|mode|number` prints one
shell-friendly value. The `~/bin/defdir` compatibility helper uses
`rwmctl current --field pwd`, so the existing `Super+Return` → `bin/term` path
starts RubyTerm in the active project's directory. An explicit
`term --dir DIRECTORY` still overrides that default.

`rwmctl` always activates the RubyWM repository's own bundle. It ignores a
Gemfile in the caller's current directory and re-execs outside an inherited
foreign `bundle exec` environment, so these commands are safe to run directly
from the project being configured.

`edit current` targets that same pointer-monitor desktop. It can claim a
currently visible empty numeric placeholder in place and give it stable
identity without allocating a different address. For example, after
`Super+5`:

```sh
rwmctl edit current \
  --key project:scratch \
  --name Scratch \
  --group Experiments \
  --pwd "$HOME/Desktop/Projects/scratch"
```

Desktop 5 is now the `Experiments` group address and Rebar shows its top
project strip. `--key` re-keys only the current EWMH desktop/view.
`--group NAME` assigns only that view; `--rekey-group NAME` renames the current
group across every one of its views. An empty view can also change between
`--mode tiled` and `--mode floating`; a non-empty view is protected.

The top project strip has a `+` control. It appends and selects an empty tiled
view in the current group, inheriting the group's working directory. Its
temporary name is `New view`; finish describing it in place with, for example:

```sh
rwmctl edit current --key project:scratch:tools --name Tools
```

A non-empty, configured, or pinned desktop is protected.
`remove --force --fallback KEY` moves clients before removal and republishes
their `_NET_WM_DESKTOP` indices.
`group next|previous|KEY` cycles the same high-level contexts Rebar displays.
`view next|previous` cycles projects/views inside the current context. Both
accept `--monitor INDEX`, making them suitable for `sxhkd` bindings even after
the initial numeric slots are exhausted. RubyWM keeps a per-monitor MRU
history, so returning to a group selects the project used there most recently;
history follows the stable desktop object when it is renumbered.

`move KEY|GROUP --first` renumbers a dynamic project/group into the first empty,
non-visible, non-reserved initial slot. `move KEY|GROUP --to NUMBER` selects an
explicit one-based Rebar number. Windows, layout, visible-monitor ownership,
and stable metadata move atomically with the desktop. Moving appended desktops
out of the tail also trims trailing empty placeholders. A move is rejected if
it would give a group that already has a numeric address a second one.

`rwmctl.rb count NUMBER` sends the standard `_NET_NUMBER_OF_DESKTOPS` request.
Count expansion creates reusable placeholders; shrinking is accepted only when
the removed tail consists entirely of empty, non-visible placeholders.

Configured desktops can opt into the same identity and metadata:

```yaml
desktops:
  number: 10
  10:
    key: workbench
    name: Workbench
    group: System
    group_root: true
    layout: floating
    desktop: true
    pinned: true
```

The root properties `_RWM_DESKTOP_KEYS`, `_RWM_DESKTOP_PROJECTS`,
`_RWM_DESKTOP_GROUPS`, `_RWM_DESKTOP_MODES`, and `_RWM_DESKTOP_FLAGS` are
aligned with `_NET_NUMBER_OF_DESKTOPS`. `_RWM_VISIBLE_DESKTOPS` contains one
desktop index per monitor. `_RWM_DESKTOP_CLIENT_COUNTS` contains the number of
managed windows assigned to each desktop, allowing a pager to hide only slots
that are genuinely empty. `_RWM_DESKTOP_HISTORY` contains one fixed-width MRU
row per monitor. `_RWM_DESKTOP_GENERATION` is written last after a coherent
update. These properties survive a WM-only restart in the same X session and
are restored before existing clients are adopted.

Project manifests and launch-on-create policy are intentionally not in the WM
yet. See [the project-screen design](docs/amiga-project-screens.md) for that
next layer, Rebar overflow/grouping, stage layouts, and per-window tabs.

## Using with sxhkd

This is my related integration with sxhkd from my sxhkd config, but any
app that supports sending XClientMessage events can work:

```
    # Full screen
    super + f
    	/home/vidarh/bin/xclimsg -mpw focused _NET_WM_STATE 2 _NET_WM_STATE_FULLSCREEN 0 2
    
    # Shift Focus
    super + {Left,Down,Up,Right}
    	/home/vidarh/bin/xclimsg -mpw focused _RWM_FOCUS {Left,Down,Up,Right}
    
    # Shift direction
    super + shift + d
    	/home/vidarh/bin/xclimsg -mpw focused _RWM_SHIFT_DIRECTION 0
    
    # Swap node layout
    super + shift + l
    	/home/vidarh/bin/xclimsg -mpw focused _RWM_SWAP_NODES 0
    
    # Move
    super + shift + {Left,Down,Up,Right}
    	/home/vidarh/bin/xclimsg -mpw focused _RWM_MOVE {Left,Down,Up,Right}
    
    super + F1
    	/home/vidarh/bin/xclimsg -mpw focused _NET_RESTACK_WINDOW 2 0 0
    
    super + F2
    	/home/vidarh/bin/xclimsg -mpw focused _NET_RESTACK_WINDOW 2 0 1
    
    # Select the high-level group at this Rebar address. Do not send
    # _NET_CURRENT_DESKTOP here: that exposes project backing desktops.
    super + {1-9,0}
        /home/vidarh/Desktop/Projects/wm/climsg.rb _RWM_VIEW_GROUP {1-9,10}
    
    # Move the focused window to the last-used project in this group.
    super + shift + {1-9,0}
        /home/vidarh/Desktop/Projects/wm/climsg.rb -w focused _RWM_SEND_TO_GROUP {1-9,10}
    
    # Assign desktop to a specific monitor (example for monitor "left")
    super + alt + 1
        /home/vidarh/bin/xclimsg -mp _RWM_SET_MONITOR 0 left
        
    # Move window to desktop shown on next monitor
    super + period
        /home/vidarh/bin/xclimsg -mp _RWM_MOVE_TO_MONITOR next
        
    # Move window to desktop shown on previous monitor
    super + comma
        /home/vidarh/bin/xclimsg -mp _RWM_MOVE_TO_MONITOR previous
```

The `_RWM` events are custom for this WM. The others works on other
EWMH compatible wms.

### The `_RWM_*` protocol

The `_RWM_*` messages are this WM's own command surface, sent as X11
`ClientMessage` events (format 32) to the root window. State, by contrast,
is published as EWMH properties (see *EWMH support* below) — commands in,
properties out.

Directions are passed by **name** (as X11 atoms), not as integers, because
they are meant to be written by hand in keybindings — `_RWM_FOCUS Left` is
self-explanatory where `_RWM_FOCUS 0` would not be. The WM resolves the atom
name once per command (not a hot path). Names are matched case-insensitively.

All of the window-oriented commands currently act on the **focused** window,
regardless of the message's target window field (so `-w focused` is
conventional but not yet load-bearing — see the `FIXME`s in `wm.rb`).

| Message | `data[0]` | Effect |
|---------|-----------|--------|
| `_RWM_FOCUS` | `Left`/`Right`/`Up`/`Down` | Move focus to the nearest window in that direction. |
| `_RWM_MOVE` | `Left`/`Right`/`Up`/`Down` | Floating window: nudge 20px that way. Tiled: swap with the nearest window in that direction. |
| `_RWM_SHIFT_DIRECTION` | *(ignored)* | Toggle the split direction (horizontal ↔ vertical) of the focused window's parent node. |
| `_RWM_SWAP_NODES` | *(ignored)* | Swap the two children of the focused window's parent node. |
| `_RWM_MOVE_TO_MONITOR` | `next`/`previous` | Move the focused window to the desktop shown on the adjacent monitor. |
| `_RWM_VIEW_DESKTOP` | desktop index | Show the desktop on the monitor in `data[1]`; `0xffffffff` means the active monitor. |
| `_RWM_VIEW_GROUP` | one-based group address | Show that context's MRU project, or the empty placeholder at an unused numeric address; `data[1]` is monitor+1, or `0` for active. |
| `_RWM_SEND_TO_GROUP` | one-based group address | Move the message/focused window to that context's MRU project, or to the empty placeholder at an unused address; `data[1]` uses the same monitor encoding. |
| `_RWM_ADD_GROUP_VIEW` | monitor+1, or `0` for active | Append and select an empty tiled view in that monitor's current group. |
| `_RWM_REMOVE_DESKTOP` | desktop index | Remove it; `data[1]` bit 0 forces and `data[2]` is the fallback index or `0xffffffff`. |
| `_RWM_ENSURE_DESKTOP` | protocol version (`1`) | Find or create the stable key described by the requester window's `_RWM_DESKTOP_SPEC`. |
| `_RWM_MOVE_DESKTOP` | protocol version (`1`) | Atomically renumber the desktop in `data[1]` into `data[2]`; `0xffffffff` selects the first reusable slot. |

`_RWM_ENSURE_DESKTOP` uses the ClientMessage's window field as a temporary
request window. Its `_RWM_DESKTOP_SPEC` is UTF-8 JSON; RubyWM writes a UTF-8
JSON `_RWM_DESKTOP_REPLY` on the same window. `rwmctl.rb` owns these mechanics
so keybindings and future project tooling do not need to.

`_RWM_SET_MONITOR` appears in the example bindings above but is **not yet
implemented** — sending it currently has no effect.

xclimsg is from https://github.com/phillbush/xclimsg
I intend to "build in" the same client code in rubywm to avoid that
external dependency. Alternatively you can e.g. use xdotool or similar
