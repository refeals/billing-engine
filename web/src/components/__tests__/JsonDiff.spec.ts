import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'

import JsonDiff from '../JsonDiff.vue'

function rowsOf(wrapper: ReturnType<typeof mount>) {
  return wrapper.findAll('tbody tr').map((row) => ({
    cells: row.findAll('td').map((cell) => cell.text()),
    changed: row.attributes('data-changed') === 'true',
  }))
}

describe('JsonDiff', () => {
  it('shows one row per key and flags the ones that changed', () => {
    const wrapper = mount(JsonDiff, {
      props: {
        before: { status: 'active', plan: 'pro' },
        after: { status: 'past_due', plan: 'pro' },
      },
    })

    expect(rowsOf(wrapper)).toEqual([
      { cells: ['status', 'active', 'past_due'], changed: true },
      { cells: ['plan', 'pro', 'pro'], changed: false },
    ])
  })

  it('marks keys that were added or removed', () => {
    const wrapper = mount(JsonDiff, {
      props: { before: { canceled_at: '2026-10-01' }, after: { paused_at: '2026-10-02' } },
    })

    expect(rowsOf(wrapper)).toEqual([
      { cells: ['canceled_at', '2026-10-01', '—'], changed: true },
      { cells: ['paused_at', '—', '2026-10-02'], changed: true },
    ])
  })

  it('pretty-prints nested values and shows the context', () => {
    const wrapper = mount(JsonDiff, {
      props: { after: { amounts: { total: 100 } }, context: { reason: 'upgrade' } },
    })

    expect(wrapper.find('tbody td:last-child').text()).toContain('"total": 100')
    expect(wrapper.find('pre').text()).toContain('"reason": "upgrade"')
  })

  it('says so when there is no payload', () => {
    expect(mount(JsonDiff).text()).toContain('No payload recorded.')
  })
})
