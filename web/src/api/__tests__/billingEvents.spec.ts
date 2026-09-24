import { describe, expect, it } from 'vitest'

import { buildQuery } from '../billingEvents'

describe('buildQuery', () => {
  it('returns an empty string without filters', () => {
    expect(buildQuery({})).toBe('')
  })

  it('encodes only the filters that have a value', () => {
    expect(
      buildQuery({ event_type: 'clock.reset', actor_type: '', from: '2026-10-01', page: '2' }),
    ).toBe('?event_type=clock.reset&from=2026-10-01&page=2')
  })
})
