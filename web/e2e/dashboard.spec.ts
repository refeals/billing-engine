import { expect, test } from '@playwright/test'

import { resetDemo } from './helpers'

test.beforeEach(async ({ request }) => {
  await resetDemo(request)
})

test('the dashboard shows the seeded figures and links to the lists behind them', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByText('Figures as of Mar 16, 2026')).toBeVisible()
  const mrr = page.getByRole('link', { name: /MRR/ })
  await expect(mrr).toContainText('$895.17')
  await expect(mrr).toContainText('from 15 paying subscriptions')
  await expect(page.getByRole('link', { name: /Open discrepancies/ })).toContainText('0')

  const pastDue = page.getByRole('link', { name: /Past due.*at risk/ })
  await expect(pastDue).toContainText('$177.00 at risk in 3 dunning cases')
  await pastDue.click()

  await expect(page).toHaveURL(/\/dunning$/)
  const notified = page.locator('section', { has: page.locator('header', { hasText: 'Notified' }) })
  await expect(notified).toContainText('Cedar Row Rowing')
})
