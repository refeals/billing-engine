# Invoice numbers are sequential and gap-free per year (BE-2026-000001), as tax authorities
# usually expect. The counter is incremented in the invoice's own transaction, so a rolled
# back invoice gives its number back instead of leaving a hole.
module InvoiceNumber
  PREFIX = "BE"

  def self.next!(year)
    unless ActiveRecord::Base.lease_connection.current_transaction.joinable?
      raise Audit::OutsideTransactionError, "InvoiceNumber.next! must run inside the invoice's transaction"
    end

    sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, Integer(year) ])
      INSERT INTO invoice_number_sequences (year, last_value) VALUES (?, 1)
      ON CONFLICT (year) DO UPDATE SET last_value = last_value + 1
      RETURNING last_value
    SQL
    value = ActiveRecord::Base.lease_connection.select_value(sql)

    format("%s-%04d-%06d", PREFIX, year, value)
  end
end
