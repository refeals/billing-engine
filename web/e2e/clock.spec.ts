import { expect, test } from '@playwright/test'

import { resetDemo } from './helpers'

test.beforeEach(async ({ request }) => {
  await resetDemo(request)
})

test('advancing the clock runs the day-3 dunning retry and every screen refreshes', async ({ page }) => {
  await page.goto('/dunning')
  const column = (title: string) =>
    page.locator('section', { has: page.locator('header', { hasText: title }) })

  await expect(page.getByTestId('clock-now')).toHaveText('Mar 16, 2026')
  await expect(column('Notified')).toContainText('Cedar Row Rowing')

  await page.getByRole('button', { name: '+3d' }).click()

  await expect(page.getByTestId('clock-now')).toHaveText('Mar 19, 2026')
  // Cedar's payment failed on Mar 15; its retry was due on the 18th and failed again.
  await expect(column('Retried')).toContainText('Cedar Row Rowing')
  await expect(column('Notified')).not.toContainText('Cedar Row Rowing')
})
