# Diffs two execution traces (TraceRun#events) as a sequence-alignment problem.
#
# Per the spec: key each event by *structural* fields (event + method + call
# depth), not raw line number, since line numbers shift between the two runs.
# Alignment is a standard LCS diff over those tokens — no bespoke algorithm.
#
# Output is a flat list of Row structs the side-by-side view renders:
#   op == :equal   -> left & right both present (optionally with a locals diff)
#   op == :removed -> only in the "before" run  (left present, right nil)
#   op == :added   -> only in the "after" run   (right present, left nil)
class TraceDiffer
  Row = Struct.new(:op, :left, :right, :locals_diff, keyword_init: true) do
    def changed_locals? = locals_diff.present?
  end

  def self.call(before_run, after_run)
    new(before_run.events, after_run.events).rows
  end

  def initialize(before_events, after_events)
    @before = Array(before_events)
    @after = Array(after_events)
  end

  def rows
    @rows ||= align.map do |op, left, right|
      Row.new(op: op, left: left, right: right,
              locals_diff: (op == :equal ? locals_diff(left, right) : nil))
    end
  end

  # Summary counts for the diff header.
  def stats
    rows.each_with_object(Hash.new(0)) do |row, acc|
      acc[row.op] += 1
      acc[:locals_changed] += 1 if row.op == :equal && row.changed_locals?
    end
  end

  private

  # Structural token — deliberately excludes file/line so shifted lines still match.
  def token(event)
    "#{event['event']}|#{event['method']}|#{event['depth']}"
  end

  # Backtrack the LCS table into a list of [op, left, right] operations.
  def align
    a = @before
    b = @after
    table = lcs_table(a.map { |e| token(e) }, b.map { |e| token(e) })

    ops = []
    i = a.size
    j = b.size
    while i.positive? || j.positive?
      if i.positive? && j.positive? && token(a[i - 1]) == token(b[j - 1])
        ops << [ :equal, a[i - 1], b[j - 1] ]
        i -= 1; j -= 1
      elsif j.positive? && (i.zero? || table[i][j - 1] >= table[i - 1][j])
        ops << [ :added, nil, b[j - 1] ]
        j -= 1
      else
        ops << [ :removed, a[i - 1], nil ]
        i -= 1
      end
    end
    ops.reverse
  end

  def lcs_table(a, b)
    table = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
    a.each_index do |i|
      b.each_index do |j|
        table[i + 1][j + 1] =
          if a[i] == b[j]
            table[i][j] + 1
          else
            [ table[i][j + 1], table[i + 1][j] ].max
          end
      end
    end
    table
  end

  # Per-step locals diff for aligned events: which local vars differ in value.
  def locals_diff(left, right)
    lv = left["locals"] || {}
    rv = right["locals"] || {}
    keys = (lv.keys | rv.keys).reject { |k| k == "%self" }
    changed = keys.filter_map do |k|
      next if lv[k] == rv[k]
      { name: k, before: lv[k], after: rv[k] }
    end
    changed.presence
  end
end
