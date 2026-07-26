require "minitest/autorun"
require_relative "../../desktop_navigation"

class TestDesktopNavigation < Minitest::Test
  SLOT = 1 << 4
  AVAILABLE = 1 << 5
  ROOT = 1 << 3

  def row(index, key: nil, name: nil, group: nil, flags: 0)
    {
      index: index,
      key: key || "desktop-#{index + 1}",
      name: name || (index + 1).to_s,
      project: nil,
      group: group,
      mode: "tiled",
      flags: flags,
      monitors: [],
    }
  end

  def navigation(current: 2, history: [])
    DesktopNavigation.new(
      [
        row(0, flags: SLOT | AVAILABLE),
        row(1),
        row(
          2,
          key: "project:rubywm",
          name: "RubyWM",
          group: "Coding",
          flags: SLOT,
        ),
        row(
          3,
          key: "project:compiler",
          name: "Compiler",
          group: "Coding",
          flags: SLOT,
        ),
        row(
          9,
          key: "workbench",
          name: "Workbench",
          group: "System",
          flags: ROOT,
        ),
      ],
      current: current,
      history: history,
    )
  end

  def test_group_cycle_uses_visible_context_order_and_skips_placeholders
    nav = navigation

    assert_equal ["2", "3: Coding", "10: System"],
                 nav.contexts.map { _1[:label] }
    assert_equal 9, nav.group_target("next")
    assert_equal 1, nav.group_target("previous")
    assert_equal 2, nav.group_target("Coding")
  end

  def test_view_cycle_stays_inside_current_group
    nav = navigation

    assert_equal 3, nav.view_target("next")
    assert_equal 3, nav.view_target("previous")
  end

  def test_group_root_is_the_group_target
    nav = navigation(current: 1)

    assert_equal 9, nav.group_target("System")
  end

  def test_group_target_returns_to_its_most_recent_project
    nav = navigation(current: 9, history: [9, 3, 2, 1])

    assert_equal 3, nav.group_target("Coding")
  end

  def test_numeric_address_targets_the_group_not_a_project_backing_desktop
    nav = DesktopNavigation.new(
      [
        row(
          2,
          key: "project:rubywm",
          name: "RubyWM",
          group: "Coding",
          flags: SLOT,
        ),
        row(
          4,
          key: "project:improve",
          name: "Improve",
          group: "Coding",
          flags: SLOT,
        ),
        row(
          9,
          key: "workbench",
          name: "Workbench",
          group: "System",
          flags: ROOT,
        ),
      ],
      current: 9,
      history: [9, 4, 2],
    )

    assert_equal 4, nav.group_target("3")
    error = assert_raises(ArgumentError) { nav.group_target("5") }
    assert_equal "unknown group: 5", error.message
  end

  def test_empty_numeric_address_remains_reachable_beside_overflow_child
    nav = DesktopNavigation.new(
      [
        row(
          2,
          key: "project:rubywm",
          name: "RubyWM",
          group: "Coding",
          flags: SLOT,
        ),
        row(4, flags: SLOT | AVAILABLE),
        row(
          10,
          key: "project:improve",
          name: "Improve",
          group: "Coding",
        ),
      ],
      current: 10,
      history: [10, 2],
    )

    assert_equal 10, nav.group_target("3")
    assert_equal 4, nav.group_target("5")
  end

  def test_occupied_unnamed_slot_is_a_context
    rows = [
      row(0, flags: SLOT | AVAILABLE).merge(occupied: true),
      row(1),
    ]
    nav = DesktopNavigation.new(rows, current: 1)

    assert_equal ["1", "2"], nav.contexts.map { _1[:label] }
  end
end
