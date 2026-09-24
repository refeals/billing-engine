class Customer < ApplicationRecord
  has_many :payment_methods, -> { order(:id) }, dependent: :restrict_with_exception
  has_many :credit_ledger_entries, dependent: :restrict_with_exception

  # Stored normalized, so uniqueness is case-insensitive without relying on collation.
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :provider_customer_id, presence: true, uniqueness: true
  validates :credit_balance_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :search, ->(query) {
    pattern = "%#{sanitize_sql_like(query.to_s.strip.downcase)}%"
    # sanitize_sql_like escapes % and _ with a backslash; SQLite only honors it with ESCAPE.
    where("LOWER(name) LIKE :pattern ESCAPE '\\' OR email LIKE :pattern ESCAPE '\\'", pattern: pattern)
  }

  def audit_references
    { customer_id: id, subscription_id: nil }
  end

  def default_payment_method
    payment_methods.find_by(is_default: true)
  end

  # The cached balance must always equal the ledger sum; used by tests and reconciliation.
  def ledger_balance_matches?
    credit_ledger_entries.sum(:amount_cents) == credit_balance_cents
  end
end
