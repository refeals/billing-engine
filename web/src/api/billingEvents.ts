import { apiRequest } from './client'
import { toQueryString } from './query'
import type { PageMeta, Paginated } from './types'

export const ACTOR_TYPES = ['admin', 'webhook', 'system_job', 'reconciliation'] as const
export type ActorType = (typeof ACTOR_TYPES)[number]

export interface BillingEvent {
  id: number
  event_type: string
  actor_type: ActorType
  subject: { type: string; id: number } | null
  subscription_id: number | null
  customer_id: number | null
  webhook_event_id: number | null
  data: {
    before?: Record<string, unknown>
    after?: Record<string, unknown>
    context?: Record<string, unknown>
  }
  occurred_at: string
  created_at: string
}

export interface BillingEventFilters {
  subscription_id?: string
  customer_id?: string
  event_type?: string
  actor_type?: string
  from?: string
  to?: string
  page?: string
}

export interface BillingEventsMeta extends PageMeta {
  event_types: string[]
}

export function fetchBillingEvents(
  filters: BillingEventFilters = {},
): Promise<Paginated<BillingEvent, BillingEventsMeta>> {
  return apiRequest(`/billing_events${toQueryString({ ...filters })}`)
}
