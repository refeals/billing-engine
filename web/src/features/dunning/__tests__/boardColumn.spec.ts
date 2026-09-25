import { describe, expect, it } from 'vitest'

import { boardColumn } from '@/api/dunning'

describe('boardColumn', () => {
  it('places open cases by the last step they went through', () => {
    expect(boardColumn({ status: 'open', last_step: 'day_0_notice' })).toBe('notified')
    expect(boardColumn({ status: 'open', last_step: 'day_3_retry' })).toBe('retried')
    expect(boardColumn({ status: 'open', last_step: 'day_7_suspend' })).toBe('suspended')
  })

  it('places closed cases by how they ended', () => {
    expect(boardColumn({ status: 'recovered', last_step: 'day_3_retry' })).toBe('recovered')
    expect(boardColumn({ status: 'exhausted', last_step: 'day_14_cancel' })).toBe('lost')
    expect(boardColumn({ status: 'canceled', last_step: 'day_0_notice' })).toBe('lost')
  })
})
