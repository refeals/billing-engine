import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'

import { INVOICE_STATUSES } from '@/api/invoices'
import InvoiceStatusBadge from '../InvoiceStatusBadge.vue'

describe('InvoiceStatusBadge', () => {
  it.each(INVOICE_STATUSES)('renders a label for %s', (status) => {
    expect(mount(InvoiceStatusBadge, { props: { status } }).text()).not.toBe('')
  })

  it('shows open invoices as something to watch', () => {
    expect(
      mount(InvoiceStatusBadge, { props: { status: 'open' } })
        .classes()
        .join(' '),
    ).toContain('text-status-past-due')
  })
})
