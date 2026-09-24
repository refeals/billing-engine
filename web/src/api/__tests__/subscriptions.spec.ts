import { afterEach, describe, expect, it, vi } from 'vitest'

import { fetchSubscriptions, runSubscriptionAction } from '../subscriptions'

function stubFetch() {
  const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('runSubscriptionAction', () => {
  it('sends the idempotency key and the lock_version the screen was loaded with', async () => {
    const fetchMock = stubFetch()

    await runSubscriptionAction({ id: 7, lock_version: 3 }, 'cancel', 'key-123', {
      at_period_end: true,
    })

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/subscriptions\/7\/cancel$/)
    expect(init.headers['Idempotency-Key']).toBe('key-123')
    expect(JSON.parse(init.body)).toEqual({ at_period_end: true, lock_version: 3 })
  })
})

describe('fetchSubscriptions', () => {
  it('only sends the filters that are set', async () => {
    const fetchMock = stubFetch()

    await fetchSubscriptions({ status: 'paused', q: '', page: 2 })

    expect(fetchMock.mock.calls[0]![0]).toMatch(/\/subscriptions\?status=paused&page=2$/)
  })
})
