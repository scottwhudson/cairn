module ApplicationHelper
  # Values whose whole contents are already on screen. rdbg hands back a
  # variablesReference for nearly every value, so `ref > 0` isn't enough to know
  # there's anything inside: expanding a nil or an Integer just yields an empty
  # list, and the caret promises a drill-down that never arrives.
  SCALAR_TYPES = %w[NilClass TrueClass FalseClass Integer Float Symbol].freeze

  # Whether a var row should offer a disclosure caret.
  def drillable?(var)
    return false unless var[:ref].to_i.positive?

    SCALAR_TYPES.exclude?(var[:type].to_s)
  end

  def input_classes
    "mt-1 block w-full rounded-md border border-slate-700 bg-slate-800 px-3 py-2 text-sm " \
      "text-slate-100 placeholder-slate-500 focus:border-sky-500 focus:outline-none focus:ring-1 focus:ring-sky-500"
  end
end
