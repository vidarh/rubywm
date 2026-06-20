# RubyWM debugging harness (`wmh`)

Runs RubyWM on a **private nested X display** so it can be driven and observed
**without touching the real session on `:0`**. Observation is by screenshot
(PNG), EWMH property dumps, window tree, and the WM log; input is driven by
`xdotool` and by RubyWM's own ClientMessage protocol (`climsg.rb`).

## Backends
- **Xvfb (default)** — fully headless, no window on `:0`, CI-friendly.
  **Recommended dev option**; install with `sudo apt-get install xvfb`.
- **Xephyr (`--watch`)** — a visible nested window so you can watch it live.
- `--dual` (two Xinerama heads) forces Xephyr, since Xvfb can't fake Xinerama
  multi-head.

Both always enable XINERAMA so RubyWM gets real monitor geometry (single-screen
Xephyr *without* it advertises a bogus 100×100 screen, which RubyWM trusts). The
Xephyr backend deliberately omits `-resizeable`: with it Xephyr defaults both
framebuffer and window to 100×100 instead of honouring `-screen`, so `--watch`
came up tiny. Without it the nested screen is the requested size and the parent
WM sizes the host window normally.

## Safety
- Picks a free display in `:7..:30`; **refuses** to run the WM on `:0` or on the
  parent `$DISPLAY` (`assert_safe_display`).
- Xephyr runs with `-no-host-grab` — never grabs your real keyboard/mouse.
- `wmh down` kills only what it started.

## Usage
```sh
export RUBYWM_REPO=/home/vidarh/Desktop/Projects/wm   # default; override if needed

wmh up [--geom 1280x800] [--dual] [--watch]   # default: headless Xvfb
wmh client xterm -e 'sleep 600'               # launch a client on the harness display
wmh msg _NET_CURRENT_DESKTOP 2                # send a ClientMessage via climsg.rb
wmh key super+2                               # send keys via xdotool
wmh shot [out.png]                            # screenshot nested root (default run/shot-N.png)
wmh props                                     # root EWMH properties
wmh tree                                      # window tree with geometries
wmh log [-f]                                  # WM log (stdout pp + stderr $logger)
wmh status                                    # display, backend, pids
wmh down                                      # tear down + clean up
```

## Notes learned while building it
- RubyWM's `pp`/`p` go to **stdout** (Ruby-buffered); `$logger` goes to **stderr**
  (unbuffered). The harness launches with `STDOUT.sync=true` so stdout is captured
  even when the WM is killed. (`stdbuf` does NOT work here — Ruby manages its own
  buffers, not glibc's.)
- Screenshots capture the nested root regardless of whether a window is visible
  on `:0`.
- Pure-logic units (node/geom split math, `find_closest`) need no X server at all
  — good first target for a headless spec suite under `test/`.
