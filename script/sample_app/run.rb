# Entrypoint the debug session launches under rdbg. It exercises the changed
# pricing code across a few carts so the tour's breakpoints get hit repeatedly
# (good for scrubbing forward/back through loop iterations).
require_relative "pricing"

CARTS = [
  [ { name: "widget",  price: 9.99,  qty: 3 },
    { name: "grommet", price: 4.50,  qty: 12 } ],       # qty 12 -> medium
  [ { name: "pallet",  price: 100.0, qty: 100 } ],       # qty 100 -> large (boundary)
  [ { name: "bolt",    price: 2.0,   qty: 10 } ]         # qty 10  -> medium (boundary)
].freeze

CARTS.each_with_index do |items, i|
  total = Pricing.cart_total(items)
  puts "cart #{i}: $#{format('%.2f', total)}"
end
