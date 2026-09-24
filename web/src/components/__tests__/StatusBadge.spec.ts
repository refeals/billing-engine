import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'

import { SUBSCRIPTION_STATUSES } from '@/api/subscriptions'
import StatusBadge from '../StatusBadge.vue'

describe('StatusBadge', () => {
  it.each(SUBSCRIPTION_STATUSES)('renders a label and its own color for %s', (status) => {
    const wrapper = mount(StatusBadge, { props: { status } })

    expect(wrapper.text()).not.toBe('')
    expect(wrapper.classes().join(' ')).toContain(`text-status-${status.replace('_', '-')}`)
  })

  it('uses a readable label', () => {
    expect(mount(StatusBadge, { props: { status: 'past_due' } }).text()).toBe('Past due')
  })
})
