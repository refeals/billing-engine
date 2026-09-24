import { describe, expect, it } from 'vitest'

import { parseMoneyToCents } from '../money'

describe('parseMoneyToCents', () => {
  it.each([
    ['49', 4900],
    ['49.9', 4990],
    ['49.90', 4990],
    ['0.29', 29],
    ['$1,049.90', 104990],
    [' 12.5 ', 1250],
  ])('parses %j as %i cents', (input, cents) => {
    expect(parseMoneyToCents(input)).toBe(cents)
  })

  it.each(['', 'abc', '1.234', '1.', '.5', '-5', '12,5'])('rejects %j', (input) => {
    expect(parseMoneyToCents(input)).toBeNull()
  })

  it('accepts negatives only when allowed', () => {
    expect(parseMoneyToCents('-12.50', { allowNegative: true })).toBe(-1250)
    expect(parseMoneyToCents('-$3', { allowNegative: true })).toBe(-300)
  })
})
