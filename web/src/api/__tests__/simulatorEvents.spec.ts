import { afterEach, describe, expect, it, vi } from 'vitest'

import { emitProviderEvent, fetchProviderEvents } from '../simulatorEvents'

function stubFetch() {
  const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('emitProviderEvent', () => {
  it('omits the status override when the provider should agree with the engine', async () => {
    const fetchMock = stubFetch()

    await emitProviderEvent({
      subscription_id: 4,
      type: 'customer.subscription.updated',
      delivery: 'drop',
      copies: 1,
    })

    const body = JSON.parse(fetchMock.mock.calls[0]![1].body)
    expect(body).toEqual({
      subscription_id: 4,
      type: 'customer.subscription.updated',
      delivery: 'drop',
      copies: 1,
    })
  })
})

describe('fetchProviderEvents', () => {
  it('filters by delivery status', async () => {
    const fetchMock = stubFetch()

    await fetchProviderEvents({ delivery_status: 'dropped' })

    expect(fetchMock.mock.calls[0]![0]).toMatch(/\/simulator\/events\?delivery_status=dropped$/)
  })
})
