import { afterEach, describe, expect, it, vi } from 'vitest'

import { fetchInvoices, retryInvoicePayment } from '../invoices'

function stubFetch() {
  const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('invoices API', () => {
  it('filters by subscription', async () => {
    const fetchMock = stubFetch()

    await fetchInvoices({ subscription_id: 3, status: '' })

    expect(fetchMock.mock.calls[0]![0]).toMatch(/\/invoices\?subscription_id=3$/)
  })

  it('retries with an idempotency key', async () => {
    const fetchMock = stubFetch()

    await retryInvoicePayment(8, 'retry-key')

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/invoices\/8\/retry_payment$/)
    expect(init.method).toBe('POST')
    expect(init.headers['Idempotency-Key']).toBe('retry-key')
  })
})
