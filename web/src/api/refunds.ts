import { apiRequest } from './client'
import { idempotencyHeaders } from './idempotency'
import type { InvoiceDetail } from './invoices'

export const REFUND_REASONS = [
  'requested_by_customer',
  'duplicate',
  'fraudulent',
  'service_issue',
] as const
export type RefundReason = (typeof REFUND_REASONS)[number]
export type RefundDestination = 'original_method' | 'credit_balance'

export interface Refund {
  id: number
  provider_refund_id: string | null
  amount_cents: number
  destination: RefundDestination
  reason: RefundReason
  status: 'pending' | 'succeeded' | 'failed'
  failure_reason: string | null
  requested_at: string
  completed_at: string | null
}

export interface RefundInput {
  amount_cents: number
  destination: RefundDestination
  reason: RefundReason
}

// Mirrors the API's rule so the form can say it before sending; the API still decides.
export function refundAmountError(cents: number | null, refundableCents: number): string | null {
  if (cents === null || cents <= 0) return 'Enter an amount like 10 or 10.50'
  if (cents > refundableCents) return 'That is more than can still be refunded'
  return null
}

export function createRefund(invoiceId: number, input: RefundInput, idempotencyKey: string) {
  return apiRequest<InvoiceDetail>(`/invoices/${invoiceId}/refunds`, {
    method: 'POST',
    body: input,
    headers: idempotencyHeaders(idempotencyKey),
  })
}
