# BEFORE state of the fix: tier boundaries use strict `>`, so an order sitting
# exactly on a threshold (qty == 10 or qty == 100) falls through to the lower
# tier and loses its discount. Kept around so we can record a "before" trace and
# diff it against the fixed version.
module Pricing
  RATE_TABLE = { small: 0.00, medium: 0.05, large: 0.10 }.freeze

  def self.discount_rate(qty)
    tier =
      if qty > 100
        :large
      elsif qty > 10
        :medium
      else
        :small
      end
    RATE_TABLE.fetch(tier)
  end

  def self.line_total(unit_price, qty)
    rate = discount_rate(qty)
    gross = unit_price * qty
    discount = gross * rate
    (gross - discount).round(2)
  end

  def self.cart_total(items)
    items.sum { |item| line_total(item[:price], item[:qty]) }
  end
end
