import { describe, expect, it } from 'vitest'

import { formatDate, formatDateTime, formatMoney } from '../format'

// Intl may use narrow no-break spaces (e.g. before "PM"); compare with plain spaces.
const normalizeSpaces = (text: string) => text.replace(/\s/g, ' ')

describe('formatMoney', () => {
  it.each([
    [0, '$0.00'],
    [1, '$0.01'],
    [1999, '$19.99'],
    [-5333, '-$53.33'],
    [123456789, '$1,234,567.89'],
  ])('formats %i cents as %s', (cents, expected) => {
    expect(formatMoney(cents)).toBe(expected)
  })
})

describe('formatDate', () => {
  it('uses UTC so late-night timestamps keep their billing date', () => {
    expect(formatDate('2026-10-01T23:30:00Z')).toBe('Oct 1, 2026')
  })
})

describe('formatDateTime', () => {
  it('includes the time and the UTC marker', () => {
    expect(normalizeSpaces(formatDateTime('2026-10-01T23:30:00Z'))).toBe(
      'Oct 1, 2026, 11:30 PM UTC',
    )
  })
})
