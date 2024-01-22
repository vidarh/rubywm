
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

It currently does *not* do anything to facilitate working on multiple
monitors, as in my current setup I'm only using a single monitor for
my Linux machine.

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

For most "normal" window managers, people tend to start the window
manager last and let it end the X session when it quits, but since
this is in development, I'm not going to do that because most stuff on
my desktop can survive my WM crashing and being restarted just fine,
as it should be, but will obviously get killed if the X session dies.

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
    
    # Focus desktop
    super + {1-9,0}
    	/home/vidarh/bin/xclimsg -mp _NET_CURRENT_DESKTOP {0-8,9}
    
    # Move to desktop
    super + shift + {1-9,0}
    	/home/vidarh/bin/xclimsg -mpw focused _NET_WM_DESKTOP {0-8,9}
```

The `_RWM` events are custom for this WM. The others works on other
EWMH compatible wms.

xclimsg is from https://github.com/phillbush/xclimsg
I intend to "build in" the same client code in rubywm to avoid that
external dependency. Alternatively you can e.g. use xdotool or similar
