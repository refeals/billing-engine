import { apiRequest } from './client'
import { toQueryString } from './query'
import type { SubscriptionStatus } from './subscriptions'
import type { Paginated } from './types'

export interface Customer {
  id: number
  name: string
  email: string
  provider_customer_id: string
  credit_balance_cents: number
  created_at: string
}

export interface PaymentMethod {
  id: number
  provider_payment_method_id: string
  test_card_token: string
  brand: string
  last4: string
  exp_month: number
  exp_year: number
  is_default: boolean
  expired: boolean
  behavior: string
}

export interface CustomerSubscriptionSummary {
  id: number
  status: SubscriptionStatus
  plan: { id: number; name: string; code: string }
  current_period_end: string
  cancel_at_period_end: boolean
}

export interface CustomerDetail extends Customer {
  payment_methods: PaymentMethod[]
  subscriptions: CustomerSubscriptionSummary[]
}

export type CreditReason =
  'downgrade_proration' | 'applied_to_invoice' | 'refund_to_balance' | 'manual_adjustment'

export interface CreditLedgerEntry {
  id: number
  amount_cents: number
  balance_after_cents: number
  reason: CreditReason
  invoice_id: number | null
  plan_change_id: number | null
  note: string | null
  occurred_at: string
}

export interface AttachPaymentMethodInput {
  test_card: string
  exp_month: number
  exp_year: number
  default: boolean
}

export function fetchCustomers(options: { q?: string; page?: number } = {}) {
  return apiRequest<Paginated<Customer>>(`/customers${toQueryString(options)}`)
}

export function fetchCustomer(id: number | string) {
  return apiRequest<CustomerDetail>(`/customers/${id}`)
}

export function createCustomer(input: { name: string; email: string }) {
  return apiRequest<CustomerDetail>('/customers', { method: 'POST', body: input })
}

export function attachPaymentMethod(customerId: number, input: AttachPaymentMethodInput) {
  return apiRequest<PaymentMethod>(`/customers/${customerId}/payment_methods`, {
    method: 'POST',
    body: input,
  })
}

export function makeDefaultPaymentMethod(customerId: number, paymentMethodId: number) {
  return apiRequest<PaymentMethod>(
    `/customers/${customerId}/payment_methods/${paymentMethodId}/make_default`,
    { method: 'POST' },
  )
}

export function fetchCreditLedger(customerId: number | string, page = 1) {
  return apiRequest<Paginated<CreditLedgerEntry>>(
    `/customers/${customerId}/credit_ledger_entries${toQueryString({ page })}`,
  )
}

export function adjustCredit(customerId: number, input: { amount_cents: number; note: string }) {
  return apiRequest<CreditLedgerEntry>(`/customers/${customerId}/credit_ledger_entries`, {
    method: 'POST',
    body: input,
  })
}
