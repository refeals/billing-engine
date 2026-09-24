import { afterEach, describe, expect, it, vi } from 'vitest'

import { createRefund, refundAmountError } from '../refunds'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('refundAmountError', () => {
  it('accepts anything up to the refundable amount', () => {
    expect(refundAmountError(4900, 4900)).toBeNull()
    expect(refundAmountError(1, 4900)).toBeNull()
  })

  it('refuses zero, unparsable and too-large amounts', () => {
    expect(refundAmountError(0, 4900)).not.toBeNull()
    expect(refundAmountError(null, 4900)).not.toBeNull()
    expect(refundAmountError(4901, 4900)).toBe('That is more than can still be refunded')
  })
})

describe('createRefund', () => {
  it('posts the refund with an idempotency key', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 201 }))
    vi.stubGlobal('fetch', fetchMock)

    await createRefund(
      3,
      { amount_cents: 1500, destination: 'credit_balance', reason: 'duplicate' },
      'refund-key',
    )

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/invoices\/3\/refunds$/)
    expect(init.headers['Idempotency-Key']).toBe('refund-key')
    expect(JSON.parse(init.body)).toEqual({
      amount_cents: 1500,
      destination: 'credit_balance',
      reason: 'duplicate',
    })
  })
})
