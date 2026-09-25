import { afterEach, describe, expect, it, vi } from 'vitest'

import { fetchDashboardSummary } from '../dashboard'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('fetchDashboardSummary', () => {
  it('reads the summary endpoint', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    await fetchDashboardSummary()

    expect(fetchMock.mock.calls[0]![0]).toMatch(/\/dashboard\/summary$/)
  })
})
