import type { BillingEvent } from './billingEvents'
import { apiRequest } from './client'
import { toQueryString } from './query'
import type { Paginated } from './types'

export const WEBHOOK_STATUSES = [
  'received',
  'processed',
  'failed',
  'skipped_stale',
  'ignored_unhandled',
] as const
export type WebhookStatus = (typeof WEBHOOK_STATUSES)[number]

export interface WebhookEvent {
  id: number
  provider_event_id: string
  event_type: string
  provider_object_id: string
  processing_status: WebhookStatus
  provider_created_at: string
  received_at: string
  processed_at: string | null
  attempts: number
  last_error: string | null
  duplicate_deliveries_count: number
  reprocessable: boolean
}

export interface WebhookEventDetail extends WebhookEvent {
  payload: Record<string, unknown>
  billing_events: BillingEvent[]
}

export function fetchWebhookEvents(options: { status?: string; page?: number } = {}) {
  return apiRequest<Paginated<WebhookEvent>>(`/webhook_events${toQueryString(options)}`)
}

export function fetchWebhookEvent(id: number | string) {
  return apiRequest<WebhookEventDetail>(`/webhook_events/${id}`)
}

export function reprocessWebhookEvent(id: number) {
  return apiRequest<{ status: string; webhook_event: WebhookEventDetail }>(
    `/webhook_events/${id}/reprocess`,
    { method: 'POST' },
  )
}
