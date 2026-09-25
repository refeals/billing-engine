module Reconciliation
  # Everything about one subscription that differs between the engine and the provider's
  # history. Returns findings (plain hashes); Run decides what to store.
  class Compare < ApplicationService
    Finding = Data.define(:kind, :subject_key, :field, :internal_value, :expected_value, :evidence_event_ids)

    def initialize(subscription)
      @subscription = subscription
    end

    # Returns the findings, or nil when the subscription can't be judged right now.
    def call
      events = FakeStripe::MockedWebhookEvent.where(provider_subscription_id: @subscription.provider_subscription_id)
        .order(:provider_created_at, :id).to_a
      # An event that hasn't been sent yet means engine and provider are mid-conversation:
      # comparing now would report differences that are about to vanish. Skip it this time.
      return nil if events.any? { |event| event.pending? && event.delivery_attempts.zero? }

      evidence = events
      expected = ProjectExpectedState.call(evidence.map { |event| { event_id: event.event_id, type: event.event_type, object: event.payload.dig("data", "object") } })

      subscription_findings(expected.subscription) + invoice_findings(expected.invoices) + delivery_findings(evidence)
    end

    private

    def subscription_findings(expected)
      return [] if expected[:status].nil?

      findings = []
      findings << finding("status_mismatch", "status", "status", @subscription.status, expected[:status], expected[:evidence][:status]) if expected[:status] != @subscription.status
      if expected[:plan] != @subscription.plan.code
        findings << finding("plan_mismatch", "plan", "plan", @subscription.plan.code, expected[:plan], expected[:evidence][:plan])
      end
      if expected[:current_period_end] != @subscription.current_period_end.to_i
        findings << finding("period_mismatch", "current_period_end", "current_period_end", @subscription.current_period_end.iso8601,
          expected[:current_period_end] && Time.zone.at(expected[:current_period_end]).iso8601, expected[:evidence][:current_period_end])
      end
      findings
    end

    def invoice_findings(expected_invoices)
      engine_invoices = @subscription.invoices.includes(:refunds).index_by(&:provider_invoice_id)

      expected_invoices.flat_map do |provider_id, expected|
        invoice = engine_invoices[provider_id]
        next [ finding("missing_invoice", provider_id, "invoice", nil, provider_id, expected[:evidence]) ] unless invoice

        # The provider only knows paid or not paid; "uncollectible" is the engine's own call.
        if expected[:paid] != invoice.paid?
          next [ finding("invoice_status_mismatch", provider_id, "status", invoice.status, expected[:paid] ? "paid" : "unpaid", expected[:evidence]) ]
        end

        amount_findings(invoice, expected)
      end
    end

    def amount_findings(invoice, expected)
      findings = []
      if expected[:paid] && expected[:amount_paid] != invoice.amount_paid_cents
        findings << finding("invoice_amount_mismatch", "#{invoice.provider_invoice_id}:amount_paid", "amount_paid_cents",
          invoice.amount_paid_cents, expected[:amount_paid], expected[:evidence])
      end
      # Refunds to the credit balance never involve the provider, so only card refunds count.
      card_refunded = invoice.refunds.select { |refund| refund.succeeded? && refund.to_original_method? }.sum(&:amount_cents)
      if expected[:amount_refunded] != card_refunded
        findings << finding("invoice_amount_mismatch", "#{invoice.provider_invoice_id}:amount_refunded", "amount_refunded_cents",
          card_refunded, expected[:amount_refunded], expected[:evidence])
      end
      findings
    end

    def delivery_findings(events)
      inbox = WebhookEvent.where(provider_event_id: events.map(&:event_id)).pluck(:provider_event_id, :processing_status).to_h
      failed_in_inbox = inbox.select { |_, status| status == "failed" }.keys.to_set
      # The inbox is the truth about what arrived: a reprocessed event is received, even if
      # the provider still has it pending for a retry that will just be a duplicate.
      received = inbox.select { |_, status| WebhookEvent::TERMINAL_STATUSES.include?(status) }.keys.to_set

      events.filter_map do |event|
        # A delivery the inbox failed is also still pending at the provider; it is one
        # problem, reported once, as the failure the operator can reprocess.
        if failed_in_inbox.include?(event.event_id)
          finding("failed_event", event.event_id, event.event_type, "failed", "processed", [ event.event_id ])
        elsif (event.dropped? || event.pending?) && !received.include?(event.event_id)
          finding("undelivered_event", event.event_id, event.event_type, "not received", event.delivery_status, [ event.event_id ])
        end
      end
    end

    def finding(kind, subject_key, field, internal_value, expected_value, evidence)
      Finding.new(kind: kind, subject_key: subject_key, field: field, internal_value: internal_value&.to_s,
        expected_value: expected_value&.to_s, evidence_event_ids: Array(evidence).uniq)
    end
  end
end
