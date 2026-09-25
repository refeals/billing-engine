import type { BillingEvent } from './billingEvents'
import { apiRequest } from './client'
import type { SubscriptionStatus } from './subscriptions'

export interface DashboardSummary {
  simulated_now: string
  subscriptions_by_status: Record<SubscriptionStatus, number>
  // active + past_due, yearly plans divided by 12 per subscription (see README).
  mrr_cents: number
  paying_subscriptions: number
  dunning: {
    open_cases: number
    amount_at_risk_cents: number
    // Keyed by the last step a case ran (day_0_notice, day_3_retry, day_7_suspend).
    by_step: Record<string, number>
  }
  open_discrepancies: number
  recent_events: BillingEvent[]
}

export function fetchDashboardSummary() {
  return apiRequest<DashboardSummary>('/dashboard/summary')
}
