require "json"

# Records a structured execution trace with TracePoint (per the spec: don't lean
# on rdbg's session-scoped record buffer for exportable traces). One event per
# call/return, capturing method, file, line, call depth, and safely-inspected
# locals. Events are keyed structurally by the differ, not by raw line number.
#
# Usage (standalone, no Rails):
#   TraceRecorder.new(base_dir: __dir__).record { load "run.rb" }.each { |e| puts JSON.generate(e) }
class TraceRecorder
  EVENTS = %i[call return b_call b_return].freeze

  # base_dir: used to relativize file paths in events.
  # only: optional absolute path — when set, record ONLY frames from that file
  #       (keeps the driver/entry script's own frames out of the trace).
  def initialize(base_dir:, only: nil, max_local_len: 200)
    @base_dir = File.expand_path(base_dir)
    @only = only && File.expand_path(only)
    @max_local_len = max_local_len
    @events = []
    @depth = 0
  end

  # Runs the block with tracing on; returns the recorded events (array of hashes).
  def record
    tp = TracePoint.new(*EVENTS) { |t| handle(t) }
    tp.enable
    yield
    self
  ensure
    tp&.disable
  end

  def events = @events

  def to_jsonl
    @events.map { |e| JSON.generate(e) }.join("\n")
  end

  private

  def handle(tp)
    return unless traced?(tp.path) # ignore stdlib / framework / driver frames

    entering = tp.event == :call || tp.event == :b_call
    @depth -= 1 if !entering && @depth.positive?

    # Capture locals on every event, not just entry: at a method's `return` the
    # binding holds the *final* local values, which is exactly where two runs of
    # the same call structure diverge (e.g. tier/discount differ by return).
    @events << {
      "event" => tp.event.to_s,
      "method" => method_label(tp),
      "file" => relative(tp.path),
      "line" => tp.lineno,
      "depth" => @depth,
      "locals" => capture_locals(tp)
    }

    @depth += 1 if entering
  end

  def method_label(tp)
    qualified = qualified_name(tp.defined_class, tp.method_id)
    tp.event.to_s.start_with?("b_") ? "block in #{qualified}" : qualified
  end

  def qualified_name(owner, method_id)
    return method_id.to_s unless owner
    if owner.singleton_class?
      # e.g. #<Class:Pricing> => "Pricing." (a module/class method)
      base = owner.inspect[/#<Class:(.+)>/, 1] || owner.inspect
      "#{base}.#{method_id}"
    else
      "#{owner}##{method_id}"
    end
  end

  def capture_locals(tp)
    bind = tp.binding
    bind.local_variables.to_h do |name|
      [ name.to_s, safe_inspect(bind.local_variable_get(name)) ]
    end
  rescue => e
    { "_error" => e.class.to_s }
  end

  def safe_inspect(value)
    str = value.inspect
    str.length > @max_local_len ? "#{str[0, @max_local_len]}…" : str
  rescue => e
    "#<uninspectable #{e.class}>"
  end

  def traced?(path)
    @only ? path == @only : path.start_with?(@base_dir)
  end

  def relative(path)
    path.start_with?("#{@base_dir}/") ? path[(@base_dir.length + 1)..] : path
  end
end
