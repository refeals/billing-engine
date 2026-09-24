import { apiRequest } from './client'
import { toQueryString } from './query'
import type { Paginated } from './types'

export type PlanInterval = 'month' | 'year'

export interface Plan {
  id: number
  code: string
  name: string
  amount_cents: number
  currency: string
  interval: PlanInterval
  trial_days: number
  active: boolean
  archived_at: string | null
}

export interface PlanInput {
  code: string
  name: string
  amount_cents: number
  interval: PlanInterval
  trial_days: number
}

export function fetchPlans(options: { includeArchived?: boolean; page?: number } = {}) {
  const query = toQueryString({ include_archived: options.includeArchived, page: options.page })
  return apiRequest<Paginated<Plan>>(`/plans${query}`)
}

export function createPlan(input: PlanInput) {
  return apiRequest<Plan>('/plans', { method: 'POST', body: input })
}

export function archivePlan(id: number) {
  return apiRequest<Plan>(`/plans/${id}/archive`, { method: 'POST' })
}
