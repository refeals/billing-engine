import { describe, expect, it } from 'vitest'

import { toQueryString } from '../query'

describe('toQueryString', () => {
  it('returns an empty string without params', () => {
    expect(toQueryString({})).toBe('')
  })

  it('encodes only the params that have a value', () => {
    expect(
      toQueryString({
        event_type: 'clock.reset',
        actor_type: '',
        from: '2026-10-01',
        page: 2,
        archived: false,
        q: null,
      }),
    ).toBe('?event_type=clock.reset&from=2026-10-01&page=2')
  })

  it('keeps true flags and escapes values', () => {
    expect(toQueryString({ include_archived: true, q: 'a&b' })).toBe(
      '?include_archived=true&q=a%26b',
    )
  })
})
