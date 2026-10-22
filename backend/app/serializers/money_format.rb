# Renders a numeric(12,2) amount as a fixed two-place string (ADR-002).
#
# BigDecimal#to_s drops trailing zeros — 50.00 becomes "50.0" — which a client
# then has to re-pad, and which reads as a different value in a price label.
# `format("%.2f")` would pad correctly but converts through Float on the way,
# the exact conversion ADR-002 exists to forbid. So the padding is done on the
# decimal's own string form.
module MoneyFormat
  def self.call(amount)
    return nil if amount.nil?

    whole, fraction = BigDecimal(amount.to_s).round(2).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(2, '0')}"
  end
end
