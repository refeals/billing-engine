class CreateInvoiceNumberSequences < ActiveRecord::Migration[8.1]
  def change
    # One counter per year, incremented in the same transaction as the invoice it numbers:
    # if the invoice rolls back, so does the increment, and the sequence never has gaps.
    create_table :invoice_number_sequences, primary_key: :year do |t|
      t.integer :last_value, null: false, default: 0
    end
  end
end
