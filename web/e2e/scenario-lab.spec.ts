import { expect, test } from '@playwright/test'

test('scenarios run from the lab, and a lost webhook is found and fixed through reconciliation', async ({ page }) => {
  test.setTimeout(90_000)
  await page.goto('/simulator')

  const card = (title: string) => page.locator('li', { has: page.getByRole('heading', { name: title }) })

  await card('Duplicate webhook').getByRole('button', { name: 'Run' }).click()
  const result = page.locator('section[aria-live="polite"]')
  await expect(result).toContainText('Duplicate webhook')
  await expect(result).toContainText('passed')
  await expect(result).toContainText('✓ the payment was recorded once')

  await card('Lost webhook').getByRole('button', { name: 'Run' }).click()
  await expect(result).toContainText('Lost webhook')
  await expect(result).toContainText('passed')

  await result.getByRole('link', { name: /Reconciliation/ }).click()
  await expect(page).toHaveURL(/\/reconciliation\?subscription_id=\d+/)
  await page.getByRole('button', { name: 'Redeliver event' }).click()
  await page.getByRole('button', { name: 'Check this subscription' }).click()

  await expect(page.getByRole('button', { name: 'Redeliver event' })).toBeHidden()
  await expect(page.getByText('Engine and provider agree')).toBeVisible()
})
