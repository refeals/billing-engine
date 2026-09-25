class ReconciliationDiscrepancySerializer
  def initialize(discrepancy)
    @discrepancy = discrepancy
  end

  def as_json(*)
    discrepancy = @discrepancy
    subscription = discrepancy.subscription
    {
      id: discrepancy.id,
      kind: discrepancy.kind,
      subject_key: discrepancy.subject_key,
      field: discrepancy.field,
      internal_value: discrepancy.internal_value,
      expected_value: discrepancy.expected_value,
      evidence_event_ids: discrepancy.evidence_event_ids,
      status: discrepancy.status,
      resolution: discrepancy.resolution,
      resolution_note: discrepancy.resolution_note,
      resolved_at: discrepancy.resolved_at&.iso8601,
      first_run_id: discrepancy.first_run_id,
      last_seen_run_id: discrepancy.last_seen_run_id,
      subscription: { id: subscription.id, status: subscription.status, customer: subscription.customer.slice(:id, :name) },
      available_resolutions: discrepancy.available_resolutions,
      blocked_resolutions: discrepancy.blocked_resolutions,
      created_at: discrepancy.created_at.iso8601
    }
  end
end
