import { apiRequest } from './client'
import { toQueryString } from './query'
import type { SubscriptionStatus } from './subscriptions'
import type { Paginated } from './types'

export const DELIVERY_STATUSES = ['pending', 'delivered', 'dropped'] as const
export type DeliveryStatus = (typeof DELIVERY_STATUSES)[number]

export const MANUAL_EVENT_TYPES = [
  'customer.subscription.updated',
  'customer.subscription.deleted',
] as const
export type ManualEventType = (typeof MANUAL_EVENT_TYPES)[number]

export interface ProviderEvent {
  id: number
  event_id: string
  event_type: string
  provider_object_id: string
  provider_subscription_id: string | null
  provider_created_at: string
  delivery_mode: 'deliver' | 'drop'
  copies: number
  delivery_status: DeliveryStatus
  delivery_count: number
  delivery_attempts: number
  last_delivery_result: string | null
  last_delivered_at: string | null
  webhook_event_id: number | null
  payload: Record<string, unknown>
}

export interface EmitEventInput {
  subscription_id: number
  type: ManualEventType
  status?: SubscriptionStatus
  delivery: 'deliver' | 'drop'
  copies: number
}

export function fetchProviderEvents(options: { delivery_status?: string; page?: number } = {}) {
  return apiRequest<Paginated<ProviderEvent>>(`/simulator/events${toQueryString(options)}`)
}

export function emitProviderEvent(input: EmitEventInput) {
  return apiRequest<ProviderEvent>('/simulator/events', { method: 'POST', body: input })
}

export function deliverProviderEvent(id: number) {
  return apiRequest<ProviderEvent>(`/simulator/events/${id}/deliver`, { method: 'POST' })
}
