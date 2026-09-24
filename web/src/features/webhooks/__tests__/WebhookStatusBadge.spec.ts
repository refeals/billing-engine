import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'

import { WEBHOOK_STATUSES } from '@/api/webhookEvents'
import WebhookStatusBadge from '../WebhookStatusBadge.vue'

describe('WebhookStatusBadge', () => {
  it.each(WEBHOOK_STATUSES)('renders a label for %s', (status) => {
    expect(mount(WebhookStatusBadge, { props: { status } }).text()).not.toBe('')
  })

  it('makes failures stand out', () => {
    const badge = mount(WebhookStatusBadge, { props: { status: 'failed' } })

    expect(badge.text()).toBe('Failed')
    expect(badge.classes().join(' ')).toContain('text-danger')
  })
})
