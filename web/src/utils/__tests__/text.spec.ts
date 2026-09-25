import { describe, expect, it } from 'vitest'

import { humanize, plural } from '../text'

describe('plural', () => {
  it('adds an s unless there is exactly one', () => {
    expect(plural(1, 'dunning case')).toBe('1 dunning case')
    expect(plural(0, 'dunning case')).toBe('0 dunning cases')
    expect(plural(3, 'difference')).toBe('3 differences')
  })
})

describe('humanize', () => {
  it('turns a key into a label', () => {
    expect(humanize('day_0_notice')).toBe('Day 0 notice')
  })
})
