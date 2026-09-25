import { apiRequest } from './client'
import { toQueryString } from './query'
import type { Paginated } from './types'

export type Resolution =
  'redeliver' | 'reprocess' | 'apply_expected' | 'resync_provider' | 'acknowledge'

export interface Discrepancy {
  id: number
  kind: string
  subject_key: string
  field: string | null
  internal_value: string | null
  expected_value: string | null
  evidence_event_ids: string[]
  status: 'open' | 'resolved' | 'acknowledged' | 'cleared'
  resolution: Resolution | null
  resolution_note: string | null
  resolved_at: string | null
  subscription: { id: number; status: string; customer: { id: number; name: string } }
  available_resolutions: Resolution[]
  blocked_resolutions: Partial<Record<Resolution, string>>
  created_at: string
}

export interface ReconciliationRun {
  id: number
  triggered_by: string
  scope_subscription_id: number | null
  subscriptions_checked: number
  discrepancies_found: number
  discrepancies_opened: number
  discrepancies_cleared: number
  started_at: string
  finished_at: string | null
}

export const RESOLUTION_LABELS: Record<Resolution, string> = {
  redeliver: 'Redeliver event',
  reprocess: 'Reprocess event',
  apply_expected: "Apply provider's value",
  resync_provider: 'Resend to provider',
  acknowledge: 'Acknowledge',
}

// Groups discrepancies by subscription, keeping the order they came in.
export function groupBySubscription(discrepancies: Discrepancy[]) {
  const groups = new Map<
    number,
    { subscription: Discrepancy['subscription']; items: Discrepancy[] }
  >()
  for (const discrepancy of discrepancies) {
    const group = groups.get(discrepancy.subscription.id) ?? {
      subscription: discrepancy.subscription,
      items: [],
    }
    group.items.push(discrepancy)
    groups.set(discrepancy.subscription.id, group)
  }
  return [...groups.values()]
}

export function fetchDiscrepancies(
  options: { status?: string; subscription_id?: string; page?: number } = {},
) {
  return apiRequest<Paginated<Discrepancy>>(
    `/reconciliation_discrepancies${toQueryString(options)}`,
  )
}

export function fetchReconciliationRuns() {
  return apiRequest<Paginated<ReconciliationRun>>('/reconciliation_runs')
}

export function runReconciliation(subscriptionId?: number) {
  return apiRequest<ReconciliationRun>('/reconciliation_runs', {
    method: 'POST',
    body: subscriptionId ? { subscription_id: subscriptionId } : {},
  })
}

export function resolveDiscrepancy(id: number, strategy: Resolution, note?: string) {
  return apiRequest<Discrepancy>(`/reconciliation_discrepancies/${id}/resolve`, {
    method: 'POST',
    body: { strategy, note },
  })
}
