
 * Figure out save sets, and consider switching back to reparenting.
 * Benefit:
  * No need to map or unmap any windows but my own.
  * Layout works exclusively on already mapped windows
  * Possible draggable screens
 * Figure out Compton issue (if it's not "magically" fixed by the above)
 * Test migration by making one desktop reparenting.
 * Figure out Dbus
 * If Synergy still doesn't work after figuring out dbus, reinstall
 * Moving nodes.
   * Crudest options:
     * Button to swap children (so not just one node)
     * Button to swap focus window up/left or down/right to nearest
       leaf.
     * Store layout direction and "split left"/"split down" options.
 * Resizes figuring out left/right/top/bottom boundaries (and which
   point better moves becomes viable.
   -> Test: Keybinding to cycle border color.
 * Figure out what keeps breaking Chrome
   * Freezes
   * Failure to open menus
   * NEED TO DOCUMENT so it doesn't break again.
 * Keybinding to kill current wm and start rubywm   
 * Keybinding to kill current wm and start tinywm
 * Receptacle node that will only swallow specific window class.
 * Keep better track of focu
 
