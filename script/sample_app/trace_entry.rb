# Records a structured execution trace of the sample app against a chosen
# pricing implementation and prints it as JSONL on stdout.
#
#   ruby script/sample_app/trace_entry.rb pricing.rb        # after (fixed)
#   ruby script/sample_app/trace_entry.rb pricing_before.rb # before (buggy)
require_relative "../../lib/trace_recorder"

impl = ARGV[0] || "pricing.rb"
require_relative File.basename(impl, ".rb")

CARTS = [
  [ { name: "widget",  price: 9.99,  qty: 3 },
    { name: "grommet", price: 4.50,  qty: 12 } ],
  [ { name: "pallet",  price: 100.0, qty: 100 } ],
  [ { name: "bolt",    price: 2.0,   qty: 10 } ]
].freeze

recorder = TraceRecorder.new(base_dir: __dir__, only: File.expand_path(impl, __dir__))
recorder.record do
  CARTS.each { |items| Pricing.cart_total(items) }
end

$stdout.write(recorder.to_jsonl)
