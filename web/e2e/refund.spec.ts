import { expect, test } from '@playwright/test'

import { createSubscription, paidInvoiceOf } from './helpers'

test('a partial card refund is recorded, and the form refuses more than what is left', async ({ page, request }) => {
  const { subscription } = await createSubscription(request)
  const invoiceId = await paidInvoiceOf(request, subscription.id)

  await page.goto(`/invoices/${invoiceId}`)
  await page.getByRole('button', { name: 'Refund', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Amount (USD)').fill('10')
  await dialog.getByRole('button', { name: 'Refund', exact: true }).click()
  await expect(dialog).toBeHidden()

  const refunds = page.locator('section', { has: page.getByRole('heading', { name: 'Refunds' }) })
  await expect(refunds).toContainText('$10.00')

  // Studio is $59.00, so $49.00 is left. The form refuses $50.00 before asking the API (which
  // refuses it too; that side is covered by RSpec).
  await page.getByRole('button', { name: 'Refund', exact: true }).click()
  await expect(dialog).toContainText('Up to $49.00 can still be refunded')
  await dialog.getByLabel('Amount (USD)').fill('50')
  await dialog.getByRole('button', { name: 'Refund', exact: true }).click()
  await expect(dialog).toContainText('That is more than can still be refunded')
  await expect(refunds).not.toContainText('$50.00')
})
