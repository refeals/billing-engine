import { afterEach, describe, expect, it, vi } from 'vitest'

import { groupBySubscription, resolveDiscrepancy, type Discrepancy } from '../reconciliation'

afterEach(() => {
  vi.unstubAllGlobals()
})

function discrepancy(id: number, subscriptionId: number): Discrepancy {
  return {
    id,
    kind: 'status_mismatch',
    subject_key: 'status',
    field: 'status',
    internal_value: 'active',
    expected_value: 'past_due',
    evidence_event_ids: [],
    status: 'open',
    resolution: null,
    resolution_note: null,
    resolved_at: null,
    subscription: { id: subscriptionId, status: 'active', customer: { id: 1, name: 'Studio' } },
    available_resolutions: ['acknowledge'],
    blocked_resolutions: {},
    created_at: '2026-10-01T00:00:00Z',
  }
}

describe('groupBySubscription', () => {
  it('groups discrepancies per subscription, in order', () => {
    const groups = groupBySubscription([discrepancy(1, 7), discrepancy(2, 8), discrepancy(3, 7)])

    expect(
      groups.map((group) => [group.subscription.id, group.items.map((item) => item.id)]),
    ).toEqual([
      [7, [1, 3]],
      [8, [2]],
    ])
  })
})

describe('resolveDiscrepancy', () => {
  it('sends the strategy and the note', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    await resolveDiscrepancy(4, 'acknowledge', 'Known test data')

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/reconciliation_discrepancies\/4\/resolve$/)
    expect(JSON.parse(init.body)).toEqual({ strategy: 'acknowledge', note: 'Known test data' })
  })
})
