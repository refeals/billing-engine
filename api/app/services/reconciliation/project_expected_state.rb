module Reconciliation
  # What the provider's own history says should be true, as a pure function of its events.
  # Events are plain hashes ({ event_id:, type:, object: }) in the order they happened.
  #
  # Subscription fields come from the provider's last subscription snapshot (the engine
  # pushes one after every committed change), with Stripe's payment rule on top: paying an
  # invoice makes a past_due or trialing subscription active, and a failed payment makes an
  # active or trialing one past_due, even before any snapshot says so.
  module ProjectExpectedState
    Expected = Data.define(:subscription, :invoices)

    def self.call(events)
      subscription = { evidence: Hash.new { |hash, key| hash[key] = [] } }
      invoices = Hash.new { |hash, id| hash[id] = { paid: false, amount_paid: 0, amount_refunded: 0, evidence: [] } }
      invoice_by_charge = {}

      events.each do |event|
        object = event[:object]
        id = event[:event_id]

        case event[:type]
        when /\Acustomer\.subscription\./
          subscription[:status] = object["status"]
          subscription[:plan] = object.dig("plan", "id")
          subscription[:current_period_end] = object["current_period_end"]
          %i[status plan current_period_end].each { |field| subscription[:evidence][field] = [ id ] }
        when "invoice.finalized"
          invoices[object["id"]][:evidence] << id
        when "invoice.paid"
          invoice = invoices[object["id"]]
          invoice.merge!(paid: true, amount_paid: object["amount_paid"].to_i)
          invoice[:evidence] << id
          set_status(subscription, "active", id) if %w[past_due trialing].include?(subscription[:status])
        when "invoice.payment_failed"
          invoices[object["id"]][:evidence] << id
          set_status(subscription, "past_due", id) if %w[active trialing].include?(subscription[:status])
        when "charge.succeeded", "charge.failed"
          invoice_by_charge[object["id"]] = object["invoice"]
        when "charge.refunded"
          invoice_id = invoice_by_charge[object["id"]]
          next unless invoice_id

          invoices[invoice_id][:amount_refunded] = object["amount_refunded"].to_i
          invoices[invoice_id][:evidence] << id
        end
      end

      Expected.new(subscription: subscription, invoices: invoices.to_h)
    end

    def self.set_status(subscription, status, event_id)
      subscription[:status] = status
      subscription[:evidence][:status] = [ event_id ]
    end
    private_class_method :set_status
  end
end
