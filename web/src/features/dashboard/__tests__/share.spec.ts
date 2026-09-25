import { describe, expect, it } from 'vitest'

import { shareOf } from '../share'

describe('shareOf', () => {
  it('is a percentage with one decimal', () => {
    expect(shareOf(1, 3)).toBe(33.3)
    expect(shareOf(12, 20)).toBe(60)
  })

  it('is zero when there is nothing to share', () => {
    expect(shareOf(0, 0)).toBe(0)
  })
})
