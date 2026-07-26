require "minitest/autorun"
require "yaml"

require_relative "../../desktop"
require_relative "../../wm"

class TestDesktopRecordMerge < Minitest::Test
  def setup
    @wm = WindowManager.allocate
    @config = YAML.load_file(File.expand_path("../../config.yml", __dir__), symbolize_names: true)
  end

  def snapshot_record(index, name:, key:, flags:)
    {
      id: index,
      name: name,
      key: key,
      group: "",
      flags: flags,
      layout: "",
      monitor: nil,
    }
  end

  def test_old_static_base_is_upgraded_without_reordering_appended_groups
    snapshot = 10.times.map do |index|
      snapshot_record(
        index,
        name: (index + 1).to_s,
        key: "desktop-#{index + 1}",
        flags: Desktop::FLAG_STATIC,
      )
    end
    snapshot[9] = snapshot_record(
      9,
      name: "Workbench",
      key: "workbench",
      flags: Desktop::FLAG_STATIC |
             Desktop::FLAG_PINNED |
             Desktop::FLAG_DESKTOP_WINDOW,
    )
    snapshot << snapshot_record(10, name: "RubyWM", key: "project:rubywm", flags: 0)
    snapshot << snapshot_record(11, name: "Novelator", key: "project:novelator", flags: 0)

    configured = @wm.configured_desktop_records(@config)
    merged = @wm.merge_desktop_records(configured, records: snapshot)

    assert_equal 12, merged.length
    assert_equal "desktop-1", merged[0][:key]
    assert_equal(
      Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE,
      merged[0][:flags],
    )
    assert_equal Desktop::FLAG_STATIC, merged[1][:flags]
    assert_equal "workbench", merged[9][:key]
    assert_equal "project:rubywm", merged[10][:key]
    assert_equal "project:novelator", merged[11][:key]
  end

  def test_secondary_group_lease_moves_to_tail_and_restores_numeric_slot
    configured = @wm.configured_desktop_records(@config)
    records = configured.map(&:dup)
    records[2] = records[2].merge(
      key: "project:rubywm",
      name: "RubyWM",
      project: "/src/rubywm",
      group: "Coding",
      flags: Desktop::FLAG_SLOT_BACKED,
    )
    records[4] = records[4].merge(
      key: "project:improve",
      name: "Improve",
      project: "/src/improve",
      group: "Coding",
      flags: Desktop::FLAG_SLOT_BACKED,
    )

    normalized, remap =
      @wm.normalize_group_child_leases(records, configured)

    assert_equal 11, normalized.length
    assert_equal "desktop-5", normalized[4][:key]
    assert_equal(
      Desktop::FLAG_SLOT_BACKED | Desktop::FLAG_AVAILABLE,
      normalized[4][:flags],
    )
    assert_equal "project:improve", normalized[10][:key]
    assert_equal 0, normalized[10][:flags]
    assert_equal({ 4 => 10 }, remap)
  end

  def test_configured_group_root_wins_over_a_legacy_child_lease
    configured = @wm.configured_desktop_records(@config)
    records = configured.map(&:dup)
    records[4] = records[4].merge(
      key: "system:utility",
      name: "Utility",
      group: "System",
      flags: Desktop::FLAG_SLOT_BACKED,
    )

    normalized, remap =
      @wm.normalize_group_child_leases(records, configured)

    assert_equal "workbench", normalized[9][:key]
    assert_equal "desktop-5", normalized[4][:key]
    assert_equal "system:utility", normalized[10][:key]
    assert_equal({ 4 => 10 }, remap)
  end
end
