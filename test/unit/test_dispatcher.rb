require "minitest/autorun"
require_relative "../../type_dispatcher"

# Dispatcher maps event classes and ClientMessage atom names to on_<name>
# handler symbols. These mappings are load-bearing for the whole event loop,
# so pin them down.
class TestDispatcher < Minitest::Test
  def setup
    @d = Dispatcher.new
  end

  # An object whose #to_s mimics an X11 event class name.
  def named(s)
    Object.new.tap { |o| o.define_singleton_method(:to_s) { s } }
  end

  def test_event_class_to_handler
    assert_equal :on_motion_notify, @d.name_to_event(named("X11::Form::MotionNotify"))
    assert_equal :on_map_request,   @d.name_to_event(named("X11::Form::MapRequest"))
    assert_equal :on_button_press,  @d.name_to_event(named("X11::Form::ButtonPress"))
  end

  def test_ewmh_atom_to_handler
    assert_equal :on_net_current_desktop, @d.name_to_event("_NET_CURRENT_DESKTOP")
    assert_equal :on_net_active_window,   @d.name_to_event("_NET_ACTIVE_WINDOW")
    assert_equal :on_net_wm_state,        @d.name_to_event("_NET_WM_STATE")
  end

  def test_rwm_atom_to_handler
    assert_equal :on_rwm_move_to_monitor, @d.name_to_event("_RWM_MOVE_TO_MONITOR")
    assert_equal :on_rwm_focus,           @d.name_to_event("_RWM_FOCUS")
  end

  def test_registered_block_takes_priority
    got = nil
    @d.on("_NET_CURRENT_DESKTOP") { |*a| got = a }
    @d.call("_NET_CURRENT_DESKTOP", 1, 2, 3)
    assert_equal [1, 2, 3], got
  end

  def test_unknown_event_is_noop
    # No handler, no target — must not raise.
    assert_nil @d.call("X11::Form::SomethingUnknown", 1, 2)
  end
end
