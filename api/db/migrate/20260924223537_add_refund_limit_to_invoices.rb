class AddRefundLimitToInvoices < ActiveRecord::Migration[8.1]
  def change
    # The last line of defense against over-refunding: whatever the code does, an invoice
    # can never have refunded more than was paid on it.
    add_check_constraint :invoices, "amount_refunded_cents <= amount_paid_cents", name: "invoices_refunds_within_paid"
  end
end
