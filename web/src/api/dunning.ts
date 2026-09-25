import { apiRequest } from './client'
import type { PaymentAttempt } from './invoices'
import { toQueryString } from './query'
import type { Paginated } from './types'

export type DunningStepName = 'day_0_notice' | 'day_3_retry' | 'day_7_suspend' | 'day_14_cancel'
export type DunningStatus = 'open' | 'recovered' | 'exhausted' | 'canceled'

export interface CustomerNotification {
  id: number
  kind: string
  subject: string
  body: string
  dunning_case_id: number | null
  sent_at: string
}

export interface DunningCase {
  id: number
  status: DunningStatus
  started_at: string
  last_step: DunningStepName | null
  next_step: DunningStepName | null
  next_step_at: string | null
  closed_at: string | null
  closed_reason: string | null
  subscription_id: number
  access_suspended: boolean
  customer: { id: number; name: string; email: string }
  invoice: {
    id: number
    number: string
    // What the invoice was for; amount_due_cents drops to 0 once a case recovers.
    total_cents: number
    amount_due_cents: number
    status: string
  }
}

export interface DunningCaseDetail extends DunningCase {
  steps: {
    id: number
    step: DunningStepName
    outcome: string
    scheduled_at: string
    executed_at: string
  }[]
  notifications: CustomerNotification[]
  payment_attempts: (PaymentAttempt & { dunning_step_id: number | null })[]
}

export const STEP_LABELS: Record<DunningStepName, string> = {
  day_0_notice: 'Day 0 · notice',
  day_3_retry: 'Day 3 · retry',
  day_7_suspend: 'Day 7 · suspend',
  day_14_cancel: 'Day 14 · cancel',
}

export type BoardColumn = 'notified' | 'retried' | 'suspended' | 'recovered' | 'lost'

// Where a case sits on the board: open cases by the last step they went through, closed
// ones by how they ended.
export function boardColumn(dunningCase: Pick<DunningCase, 'status' | 'last_step'>): BoardColumn {
  if (dunningCase.status === 'recovered') return 'recovered'
  if (dunningCase.status !== 'open') return 'lost'
  if (dunningCase.last_step === 'day_7_suspend') return 'suspended'
  if (dunningCase.last_step === 'day_3_retry') return 'retried'
  return 'notified'
}

export function fetchDunningCases(options: { status?: 'open' | 'closed'; page?: number } = {}) {
  return apiRequest<Paginated<DunningCase>>(`/dunning_cases${toQueryString(options)}`)
}

export function fetchCustomerNotifications(customerId: number | string) {
  return apiRequest<Paginated<CustomerNotification>>(`/customers/${customerId}/notifications`)
}
