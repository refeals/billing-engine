import { apiRequest } from './client'
import { idempotencyHeaders } from './idempotency'

export type PlanChangeKind = 'upgrade' | 'downgrade' | 'lateral' | 'trial_swap'
export type PlanChangeStrategy = 'immediate' | 'at_period_end'

interface PlanSummary {
  id: number
  code: string
  name: string
  amount_cents: number
}

export interface PlanChange {
  id: number
  kind: PlanChangeKind
  strategy: PlanChangeStrategy
  status: 'scheduled' | 'applied' | 'canceled'
  from_plan: PlanSummary
  to_plan: PlanSummary
  proration_date: string | null
  effective_at: string
  credit_cents: number
  charge_cents: number
  net_cents: number
  invoice_id: number | null
  created_at: string
}

export interface PlanChangeQuote {
  kind: PlanChangeKind
  strategy: PlanChangeStrategy
  allowed_strategies: PlanChangeStrategy[]
  from_plan: PlanSummary
  to_plan: PlanSummary
  proration_date: string | null
  quote_token: string
  effective_at: string
  remaining_ratio: string | null
  lines: { kind: string; description: string; amount_cents: number }[]
  credit_cents: number
  charge_cents: number
  net_cents: number
  credit_applied_cents: number
  amount_due_now_cents: number
  credit_to_balance_cents: number
}

export function previewPlanChange(
  subscriptionId: number,
  input: { plan_id: number; strategy?: PlanChangeStrategy },
) {
  return apiRequest<PlanChangeQuote>(`/subscriptions/${subscriptionId}/plan_change_preview`, {
    method: 'POST',
    body: input,
  })
}

// Sends back the preview's signed quote token: the server reuses the proration date it
// computed, so the amounts can't differ from what was shown.
export function applyPlanChange(
  subscription: { id: number; lock_version: number },
  quote: Pick<PlanChangeQuote, 'to_plan' | 'strategy' | 'quote_token'>,
  idempotencyKey: string,
) {
  return apiRequest<PlanChange>(`/subscriptions/${subscription.id}/plan_changes`, {
    method: 'POST',
    body: {
      plan_id: quote.to_plan.id,
      strategy: quote.strategy,
      quote_token: quote.quote_token,
      lock_version: subscription.lock_version,
    },
    headers: idempotencyHeaders(idempotencyKey),
  })
}

export function fetchPlanChanges(subscriptionId: number | string) {
  return apiRequest<{ data: PlanChange[] }>(`/subscriptions/${subscriptionId}/plan_changes`)
}

export function cancelScheduledPlanChange(subscriptionId: number, planChangeId: number) {
  return apiRequest<PlanChange>(
    `/subscriptions/${subscriptionId}/plan_changes/${planChangeId}/cancel`,
    {
      method: 'POST',
    },
  )
}
