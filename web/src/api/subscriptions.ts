import { apiRequest } from './client'
import { idempotencyHeaders } from './idempotency'
import type { DunningCaseDetail } from './dunning'
import type { PlanChange } from './planChanges'
import type { Plan } from './plans'
import { toQueryString } from './query'
import type { Paginated } from './types'

export const SUBSCRIPTION_STATUSES = [
  'trialing',
  'active',
  'past_due',
  'paused',
  'canceled',
] as const
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number]

export type SubscriptionAction =
  'cancel_now' | 'cancel_at_period_end' | 'undo_cancel' | 'pause' | 'resume' | 'change_plan'

export interface Subscription {
  id: number
  provider_subscription_id: string
  status: SubscriptionStatus
  customer: { id: number; name: string; email: string }
  plan: Plan
  current_period_start: string
  current_period_end: string
  trial_ends_at: string | null
  cancel_at_period_end: boolean
  canceled_at: string | null
  cancellation_reason: string | null
  paused_at: string | null
  resumes_at: string | null
  access_suspended: boolean
  lock_version: number
  allowed_actions: SubscriptionAction[]
  // Only on the subscription detail (they cost queries per row, so lists leave them out).
  default_payment_method?: {
    id: number
    brand: string
    last4: string
    exp_month: number
    exp_year: number
    expired: boolean
    behavior: string
  } | null
  scheduled_plan_change?: PlanChange | null
  open_dunning_case?: DunningCaseDetail | null
  open_discrepancies_count?: number
  created_at: string
}

export interface SubscriptionStateTransition {
  id: number
  from_status: SubscriptionStatus | null
  to_status: SubscriptionStatus
  reason: string
  actor_type: string
  billing_event_id: number
  occurred_at: string
}

export function fetchSubscriptions(options: { status?: string; q?: string; page?: number } = {}) {
  return apiRequest<Paginated<Subscription>>(`/subscriptions${toQueryString(options)}`)
}

export function fetchSubscription(id: number | string) {
  return apiRequest<Subscription>(`/subscriptions/${id}`)
}

export function fetchStateTransitions(id: number | string) {
  return apiRequest<{ data: SubscriptionStateTransition[] }>(
    `/subscriptions/${id}/state_transitions`,
  )
}

export function createSubscription(
  input: { customer_id: number; plan_id: number },
  idempotencyKey: string,
) {
  return apiRequest<Subscription>('/subscriptions', {
    method: 'POST',
    body: input,
    headers: idempotencyHeaders(idempotencyKey),
  })
}

type ActionEndpoint = 'cancel' | 'undo_cancel' | 'pause' | 'resume'

// Every change carries the lock_version the screen was loaded with; the API answers 409 if
// the subscription changed in the meantime.
export function runSubscriptionAction(
  subscription: Pick<Subscription, 'id' | 'lock_version'>,
  endpoint: ActionEndpoint,
  idempotencyKey: string,
  body: Record<string, unknown> = {},
) {
  return apiRequest<Subscription>(`/subscriptions/${subscription.id}/${endpoint}`, {
    method: 'POST',
    body: { ...body, lock_version: subscription.lock_version },
    headers: idempotencyHeaders(idempotencyKey),
  })
}
