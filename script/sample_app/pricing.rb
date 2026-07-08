# A tiny "app under review": volume-discount pricing.
#
# This file is the AFTER state of a bug fix. The PR corrected the tier
# boundaries so that an order sitting exactly on a threshold (qty == 10 or
# qty == 100) gets the discount it's entitled to. The tour's waypoints point at
# the two changed lines.
module Pricing
  RATE_TABLE = { small: 0.00, medium: 0.05, large: 0.10 }.freeze

  # Discount tier for a quantity. FIX: boundaries are now inclusive (>=),
  # so qty == 10 lands in :medium and qty == 100 in :large.
  def self.discount_rate(qty)
    tier =
      if qty >= 100
        :large
      elsif qty >= 10
        :medium
      else
        :small
      end
    RATE_TABLE.fetch(tier)
  end

  # Total for a single line item: gross less the volume discount.
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
