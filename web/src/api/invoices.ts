import { apiRequest } from './client'
import type { Refund } from './refunds'
import { idempotencyHeaders } from './idempotency'
import { toQueryString } from './query'
import type { Paginated } from './types'

export const INVOICE_STATUSES = ['open', 'paid', 'void', 'uncollectible'] as const
export type InvoiceStatus = (typeof INVOICE_STATUSES)[number]

export interface Invoice {
  id: number
  number: string
  provider_invoice_id: string
  status: InvoiceStatus
  billing_reason: string
  subscription_id: number
  customer: { id: number; name: string; email: string }
  period_start: string
  period_end: string
  subtotal_cents: number
  credit_applied_cents: number
  total_cents: number
  amount_paid_cents: number
  amount_refunded_cents: number
  amount_due_cents: number
  currency: string
  issued_at: string
  paid_at: string | null
  attempt_count: number
  payable: boolean
}

export interface InvoiceLineItem {
  id: number
  kind: 'subscription' | 'proration_credit' | 'proration_charge' | 'credit_applied'
  description: string
  amount_cents: number
  period_start: string | null
  period_end: string | null
}

export interface PaymentAttempt {
  id: number
  provider_charge_id: string
  status: 'succeeded' | 'failed'
  failure_code: string | null
  amount_cents: number
  attempted_at: string
  webhook_event_id: number | null
  card: { brand: string; last4: string } | null
}

export interface InvoiceDetail extends Invoice {
  line_items: InvoiceLineItem[]
  payment_attempts: PaymentAttempt[]
  refunds: Refund[]
  refundable_cents: number
}

export function fetchInvoices(
  options: { status?: string; subscription_id?: number | string; page?: number } = {},
) {
  return apiRequest<Paginated<Invoice>>(`/invoices${toQueryString(options)}`)
}

export function fetchInvoice(id: number | string) {
  return apiRequest<InvoiceDetail>(`/invoices/${id}`)
}

export function retryInvoicePayment(id: number, idempotencyKey: string) {
  return apiRequest<InvoiceDetail>(`/invoices/${id}/retry_payment`, {
    method: 'POST',
    headers: idempotencyHeaders(idempotencyKey),
  })
}
