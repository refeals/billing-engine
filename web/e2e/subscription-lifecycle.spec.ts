import { expect, test } from '@playwright/test'

test('create a customer, add a card, subscribe, then schedule and undo a cancellation', async ({ page }) => {
  const name = `E2E Lifecycle ${Date.now().toString(36)}`

  await page.goto('/customers')
  await page.getByRole('button', { name: 'New customer' }).click()
  await page.getByLabel('Studio name').fill(name)
  await page.getByLabel('Billing email').fill(`${Date.now().toString(36)}@lifecycle.test`)
  await page.getByRole('button', { name: 'Create customer' }).click()
  await expect(page.getByRole('heading', { name })).toBeVisible()

  await page.getByRole('button', { name: 'Add test card' }).click()
  await page.getByLabel('Test card').selectOption('pm_card_visa')
  await page.getByRole('button', { name: 'Add card' }).click()
  await expect(page.getByRole('dialog')).toBeHidden()

  await page.getByRole('button', { name: 'New subscription' }).click()
  await page.getByLabel('Plan').selectOption({ label: 'Studio · $59.00 / month' })
  await page.getByRole('button', { name: 'Create subscription' }).click()

  // The detail page of the new subscription.
  await expect(page).toHaveURL(/\/subscriptions\/\d+$/)
  await expect(page.getByRole('heading', { name: 'Studio', exact: true })).toBeVisible()
  await expect(page.getByText('Active', { exact: true }).first()).toBeVisible()

  await page.getByRole('button', { name: 'Cancel', exact: true }).click()
  await page.getByLabel(/At the end of the period/).check()
  await page.getByRole('button', { name: 'Schedule cancellation' }).click()
  await expect(page.getByText(/Scheduled to cancel on/)).toBeVisible()

  await page.getByRole('button', { name: 'Keep subscription' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Keep subscription' }).click()
  await expect(page.getByText(/Scheduled to cancel on/)).toBeHidden()

  await page.getByRole('link', { name: 'Full audit history →' }).click()
  await expect(page.getByText('subscription.cancellation_scheduled')).toBeVisible()
})
