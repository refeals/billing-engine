import { afterEach, describe, expect, it, vi } from 'vitest'

import { applyPlanChange, previewPlanChange } from '../planChanges'

function stubFetch() {
  const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('plan changes API', () => {
  it('asks the API for a preview', async () => {
    const fetchMock = stubFetch()

    await previewPlanChange(5, { plan_id: 9, strategy: 'at_period_end' })

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/subscriptions\/5\/plan_change_preview$/)
    expect(JSON.parse(init.body)).toEqual({ plan_id: 9, strategy: 'at_period_end' })
  })

  it("applies with the preview's signed token, the loaded lock_version and an idempotency key", async () => {
    const fetchMock = stubFetch()
    const plan = { id: 9, code: 'pro', name: 'Pro', amount_cents: 9900 }

    await applyPlanChange(
      { id: 5, lock_version: 7 },
      { to_plan: plan, strategy: 'immediate', quote_token: 'signed-token' },
      'change-key',
    )

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/subscriptions\/5\/plan_changes$/)
    expect(init.headers['Idempotency-Key']).toBe('change-key')
    expect(JSON.parse(init.body)).toEqual({
      plan_id: 9,
      strategy: 'immediate',
      quote_token: 'signed-token',
      lock_version: 7,
    })
  })
})
