require "minitest/autorun"

require_relative "../../desktop"
require_relative "../../wm"

class TestDesktopHistory < Minitest::Test
  Monitor = Struct.new(:id, :active_desktop)
  Client = Struct.new(:desktop)

  def setup
    @wm = WindowManager.allocate
    @desktops = 4.times.map do |index|
      Desktop.new(@wm, index, (index + 1).to_s)
    end
    @monitor = Monitor.new(0, @desktops[2])
    @wm.instance_variable_set(:@desktops, @desktops)
    @wm.instance_variable_set(:@monitors, [@monitor])
    @wm.instance_variable_set(:@windows, {})
  end

  def test_history_restores_and_tracks_desktop_objects_across_renumbering
    snapshot = {
      records: Array.new(4) { {} },
      history: [2, 1, 0, WindowManager::UINT32_MAX],
    }
    @wm.restore_desktop_history(snapshot)

    moved = @desktops[2]
    displaced = @desktops[0]
    @desktops[0] = moved
    @desktops[2] = displaced
    moved.id = 0
    displaced.id = 2

    assert_equal [0, 1, 2, WindowManager::UINT32_MAX],
                 @wm.desktop_history_indices
  end

  def test_remembering_a_desktop_makes_it_most_recent
    @wm.restore_desktop_history(records: Array.new(4) { {} }, history: [])
    @wm.remember_desktop(@monitor, @desktops[1])

    assert_equal [1, 2], @wm.desktop_history_indices.first(2)
  end

  def test_client_counts_are_aligned_with_desktop_numbers
    clients = [
      Client.new(@desktops[0]),
      Client.new(@desktops[0]),
      Client.new(@desktops[2]),
    ]
    @wm.instance_variable_set(
      :@windows,
      clients.each_with_index.to_h { |client, index| [index, client] },
    )

    assert_equal [2, 0, 1, 0], @wm.desktop_client_counts
  end

  def test_numeric_group_address_cannot_select_a_child_backing_number
    @desktops[2].key = "project:rubywm"
    @desktops[2].name = "RubyWM"
    @desktops[2].group = "Coding"
    @desktops[3].key = "project:improve"
    @desktops[3].name = "Improve"
    @desktops[3].group = "Coding"
    @monitor.active_desktop = @desktops[0]
    @wm.restore_desktop_history(
      records: Array.new(4) { {} },
      history: [0, 3, 2, WindowManager::UINT32_MAX],
    )

    assert_equal 3, @wm.desktop_for_group_address(3, @monitor)
    assert_raises(ArgumentError) {
      @wm.desktop_for_group_address(4, @monitor)
    }
  end

  def test_move_cannot_give_one_group_a_second_numeric_address
    @wm.instance_variable_set(:@initial_desktop_count, 4)
    @desktops[2].key = "project:rubywm"
    @desktops[2].name = "RubyWM"
    @desktops[2].group = "Coding"
    @desktops[2].flags = Desktop::FLAG_SLOT_BACKED
    @desktops[3].flags =
      Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE

    improve = Desktop.new(
      @wm,
      4,
      "Improve",
      key: "project:improve",
      group: "Coding",
    )
    @desktops << improve

    result = @wm.move_desktop(4, target_index: 3, publish: false)

    refute result[:ok]
    assert_equal "group already has a numeric desktop address", result[:error]
    assert_same improve, @desktops[4]
    assert @desktops[3].available_placeholder?
  end

  def test_configured_group_root_makes_a_slot_backed_child_secondary
    @wm.instance_variable_set(:@initial_desktop_count, 4)
    @desktops[1].group = "System"
    @desktops[1].flags =
      Desktop::FLAG_STATIC | Desktop::FLAG_GROUP_ROOT
    @desktops[3].group = "System"
    @desktops[3].flags = Desktop::FLAG_SLOT_BACKED

    assert @wm.secondary_group_slot?(@desktops[3])
    refute @wm.secondary_group_slot?(@desktops[1])
  end

  def test_update_only_ensure_refuses_a_missing_key
    error = assert_raises(ArgumentError) do
      @wm.ensure_desktop("key" => "project:typo", "update_only" => true)
    end

    assert_equal "desktop key does not exist: project:typo", error.message
    assert_equal 4, @desktops.length
  end

  def test_edit_can_claim_and_rekey_the_current_placeholder_in_place
    desktop = @desktops[2]
    desktop.flags = Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE
    @wm.instance_variable_set(:@initial_desktop_count, 4)
    @wm.define_singleton_method(:publish_desktop_state) {}

    result = @wm.ensure_desktop(
      "key" => "desktop-3",
      "update_only" => true,
      "new_key" => "project:scratch",
      "name" => "Scratch",
      "project" => "/src/scratch",
      "group" => "Experiments",
    )

    assert result[:ok]
    assert_equal 2, result[:desktop]
    assert_equal "project:scratch", result[:key]
    assert_equal "Scratch", desktop.name
    assert_equal "/src/scratch", desktop.project
    assert_equal "Experiments", desktop.group
    assert desktop.slot_backed?
    refute desktop.available_placeholder?
  end

  def test_group_rekey_updates_every_view_in_the_group
    @desktops[1].group = "Scratch"
    @desktops[2].group = "Scratch"
    @desktops[1].key = "project:scratch"
    @desktops[2].key = "project:scratch:tools"
    @wm.instance_variable_set(:@initial_desktop_count, 4)
    @wm.define_singleton_method(:publish_desktop_state) {}

    @wm.ensure_desktop(
      "key" => "project:scratch",
      "update_only" => true,
      "rename_group" => "Experiments",
    )

    assert_equal ["Experiments", "Experiments"],
                 @desktops.values_at(1, 2).map(&:group)
  end
end
