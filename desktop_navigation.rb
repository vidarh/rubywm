class DesktopNavigation
  FLAG_GROUP_ROOT = 1 << 3
  FLAG_AVAILABLE = 1 << 5

  attr_reader :rows, :current, :contexts, :history

  def initialize(rows, current:, history: [])
    @rows = rows
    @current = current
    @history = history
    @contexts = build_contexts
  end

  def group_target(reference)
    raise ArgumentError, "group reference is required" if reference.nil?
    reference = reference.to_s
    context = if %w[next previous].include?(reference)
      cycle(contexts, active_context, reference)
    elsif reference.match?(/\A[1-9]\d*\z/)
      number = Integer(reference)
      addressed = contexts.find { context_address(_1) + 1 == number }
      return addressed_target(addressed) if addressed

      # Empty numeric slots are intentionally omitted from the visible context
      # list, but their keyboard address remains valid. Never fall back to a
      # non-placeholder row: that would expose a child project's backing index.
      placeholder = rows.find do |row|
        row[:index] == number - 1 &&
          row[:flags].to_i & FLAG_AVAILABLE != 0 &&
          row[:group].to_s.strip.empty?
      end
      return placeholder[:index] if placeholder
      nil
    else
      contexts.find do |candidate|
        candidate[:key] == reference ||
          candidate[:label].casecmp?(reference)
      end
    end
    raise ArgumentError, "unknown group: #{reference}" unless context
    addressed_target(context)
  end

  def addressed_target(context)
    remembered = history.filter_map do |index|
      context[:records].find { _1[:index] == index }
    end.first
    (remembered || context[:root] || context[:records].first)[:index]
  end

  def view_target(direction)
    unless %w[next previous].include?(direction)
      raise ArgumentError, "view cycle must be next or previous"
    end
    context = active_context
    raise ArgumentError, "current desktop has no context" unless context
    views = if context[:root]
      context[:records].reject { _1[:key] == context[:root][:key] }
    else
      context[:records]
    end
    views = context[:records] if views.empty?
    current_row = views.find { _1[:index] == current }
    cycle(views, current_row, direction)[:index]
  end

  private

  def context_address(context)
    (context[:root] || context[:records].first)[:index]
  end

  def active_context
    contexts.find { _1[:records].any? { |row| row[:index] == current } }
  end

  def cycle(items, item, direction)
    return items.first if item.nil?
    offset = direction == "next" ? 1 : -1
    items[(items.index(item) + offset) % items.length]
  end

  def label_for(row, number: false)
    desktop_number = row[:index] + 1
    name = row[:name].to_s.strip
    return desktop_number.to_s if name.empty? || name == desktop_number.to_s
    number ? "#{desktop_number}: #{name}" : name
  end

  def build_contexts
    contexts = []
    grouped = {}
    rows.each do |row|
      next if row[:flags].to_i & FLAG_AVAILABLE != 0 &&
              row[:index] != current &&
              !row[:occupied]

      group = row[:group].to_s.strip
      if group.empty?
        contexts << {
          key: row[:key],
          label: label_for(row, number: true),
          records: [row],
          root: row,
        }
        next
      end

      context = grouped[group] ||= {
        key: group,
        label: group,
        records: [],
        root: nil,
      }.tap { contexts << _1 }
      context[:records] << row
      if row[:flags].to_i & FLAG_GROUP_ROOT != 0
        context[:root] = row
      end
    end
    contexts.each do |context|
      next if context[:root] && context[:records].length == 1 &&
              context[:key] == context[:records].first[:key]
      next unless grouped.key?(context[:key])
      context[:label] = "#{context_address(context) + 1}: #{context[:key]}"
    end
    contexts
  end
end
