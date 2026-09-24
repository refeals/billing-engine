class CreditLedgerEntrySerializer
  def initialize(entry)
    @entry = entry
  end

  def as_json(*)
    {
      id: @entry.id,
      amount_cents: @entry.amount_cents,
      balance_after_cents: @entry.balance_after_cents,
      reason: @entry.reason,
      invoice_id: @entry.invoice_id,
      plan_change_id: @entry.plan_change_id,
      note: @entry.note,
      occurred_at: @entry.occurred_at.iso8601
    }
  end
end
