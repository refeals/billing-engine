module Api
  module V1
    class InvoicesController < BaseController
      include Pagination

      def index
        scope = Invoice.includes(:customer).newest_first
        scope = scope.where(status: status_filter) if params[:status].present?
        scope = scope.where(subscription_id: params[:subscription_id]) if params[:subscription_id].present?
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
        invoices, meta = paginate(scope)

        render json: { data: invoices.map { |invoice| InvoiceSerializer.new(invoice) }, meta: meta }
      end

      def show
        render json: InvoiceSerializer.new(invoice, detail: true)
      end

      # Asks the provider to try again with the customer's current default card. The result
      # arrives as a webhook, which has already been processed by the time this responds.
      def retry_payment
        unless invoice.open_for_payment?
          raise DomainError.new("Invoice #{invoice.number} has nothing to collect (#{invoice.status})",
            code: "invoice_not_payable", details: { status: invoice.status, amount_due_cents: invoice.amount_due_cents })
        end

        ActiveRecord::Base.transaction do
          Audit.record(event_type: "invoice.payment_retry_requested", subject: invoice,
            context: { attempt_count: invoice.attempt_count, amount_due_cents: invoice.amount_due_cents })
          Invoices::RequestPayment.call(invoice)
        end

        render json: InvoiceSerializer.new(invoice.reload, detail: true)
      end

      private

      def invoice
        @invoice ||= Invoice.includes(:customer, :subscription).find(params[:id])
      end

      def status_filter
        return params[:status] if Invoice::STATUSES.include?(params[:status])

        raise DomainError.new("status must be one of #{Invoice::STATUSES.join(', ')}",
          code: "invalid_filter", details: { status: params[:status] })
      end
    end
  end
end
