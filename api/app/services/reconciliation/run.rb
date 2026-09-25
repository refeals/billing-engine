module Reconciliation
  # Compares every subscription in scope and records what differs. Nothing is corrected
  # here: new differences are opened, known ones are updated, and ones that stopped being
  # true (for example, the provider's retry finally went through) are marked cleared.
  class Run < ApplicationService
    def initialize(triggered_by:, subscription: nil)
      @triggered_by = triggered_by
      @subscription = subscription
    end

    def call
      Current.set(actor: "reconciliation") do
        ActiveRecord::Base.transaction do
          @run = ReconciliationRun.create!(triggered_by: @triggered_by, scope_subscription: @subscription,
            started_at: BillingClock.now)
          subscriptions = @subscription ? [ @subscription ] : Subscription.includes(:plan, customer: []).order(:id).to_a

          checked = []
          seen = subscriptions.flat_map do |subscription|
            findings = Compare.call(subscription)
            # Skipped (events in flight): its known discrepancies stay as they are.
            next [] if findings.nil?

            checked << subscription.id
            findings.filter_map { |finding| record(subscription, finding) unless acknowledged?(subscription, finding) }
          end
          cleared = clear_resolved_elsewhere(checked, seen.map(&:id))

          @run.update!(finished_at: BillingClock.now, subscriptions_checked: checked.size,
            discrepancies_found: seen.size, discrepancies_opened: @opened.to_i, discrepancies_cleared: cleared)
          Audit.record(event_type: "reconciliation.completed", subject: @run,
            context: @run.slice(:subscriptions_checked, :discrepancies_found, :discrepancies_opened, :discrepancies_cleared))
          @run
        end
      end
    end

    private

    # The operator already accepted exactly this difference; reporting it again every day
    # would make acknowledging pointless. A different value is a new difference.
    def acknowledged?(subscription, finding)
      ReconciliationDiscrepancy.acknowledged.exists?(subscription: subscription, kind: finding.kind,
        subject_key: finding.subject_key, internal_value: finding.internal_value, expected_value: finding.expected_value)
    end

    def record(subscription, finding)
      attributes = finding.to_h.slice(:field, :internal_value, :expected_value, :evidence_event_ids).merge(last_seen_run: @run)
      existing = ReconciliationDiscrepancy.open.find_by(subscription: subscription, kind: finding.kind, subject_key: finding.subject_key)
      return existing.tap { |discrepancy| discrepancy.update!(attributes) } if existing

      @opened = @opened.to_i + 1
      discrepancy = ReconciliationDiscrepancy.create!(attributes.merge(subscription: subscription, kind: finding.kind,
        subject_key: finding.subject_key, first_run: @run))
      Audit.record(event_type: "discrepancy.detected", subject: discrepancy,
        context: finding.to_h.slice(:kind, :field, :internal_value, :expected_value, :evidence_event_ids))
      discrepancy
    end

    # Returns how many were cleared.
    def clear_resolved_elsewhere(subscription_ids, seen_ids)
      stale = ReconciliationDiscrepancy.open.where(subscription_id: subscription_ids).where.not(id: seen_ids).to_a
      stale.each do |discrepancy|
        discrepancy.update!(status: "cleared", resolved_at: BillingClock.now, last_seen_run: @run)
        Audit.record(event_type: "discrepancy.cleared", subject: discrepancy, context: { kind: discrepancy.kind })
      end
      stale.size
    end
  end
end
