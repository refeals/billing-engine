module Proration
  # What a mid-period plan change is worth, as a pure function of prices and dates.
  #
  #   ratio  = time left in the period / length of the period
  #   credit = -(old price × ratio)   the unused part of what was paid
  #   charge =   new price × ratio    the new plan for the time left
  #   net    = credit + charge
  #
  # Times are converted with to_r, so the ratio is an exact Rational and no float error
  # creeps in. Each line is rounded (half up, to the cent) on its own, so the lines on the
  # invoice always add up to exactly the net shown in the preview.
  module Calculate
    Result = Data.define(:ratio, :credit_cents, :charge_cents, :net_cents)

    def self.call(old_amount_cents:, new_amount_cents:, period_start:, period_end:, proration_date:)
      unless period_start <= proration_date && proration_date <= period_end
        raise ArgumentError, "proration_date must fall inside the period"
      end

      ratio = (period_end.to_r - proration_date.to_r) / (period_end.to_r - period_start.to_r)
      credit = -(old_amount_cents * ratio).round(half: :up)
      charge = (new_amount_cents * ratio).round(half: :up)

      Result.new(ratio: ratio, credit_cents: credit, charge_cents: charge, net_cents: credit + charge)
    end
  end
end
