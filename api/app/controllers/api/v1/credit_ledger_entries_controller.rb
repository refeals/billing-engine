module Api
  module V1
    class CreditLedgerEntriesController < BaseController
      include Pagination

      def index
        entries, meta = paginate(customer.credit_ledger_entries.newest_first)
        render json: { data: entries.map { |entry| CreditLedgerEntrySerializer.new(entry) }, meta: meta }
      end

      # Manual adjustment by the operator: a signed amount (positive grants credit, negative
      # removes it) and a mandatory note explaining why.
      def create
        amount_cents = parse_amount
        note = params.require(:note)
        direction = amount_cents.positive? ? :credit! : :debit!

        entry = CreditLedger.public_send(direction, customer, amount_cents: amount_cents.abs, reason: "manual_adjustment", note: note)
        render json: CreditLedgerEntrySerializer.new(entry), status: :created
      end

      private

      def customer
        @customer ||= Customer.find(params[:customer_id])
      end

      def parse_amount
        amount = Integer(params.require(:amount_cents).to_s, 10, exception: false)
        return amount if amount&.nonzero?

        raise DomainError.new("amount_cents must be a non-zero whole number of cents", code: "invalid_amount",
          details: { amount_cents: params[:amount_cents] })
      end
    end
  end
end
